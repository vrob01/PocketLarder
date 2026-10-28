package larder

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const usage = `usage:
  pocketlarder serve
  pocketlarder invite <name>
  pocketlarder invite --new-admin <name>
  pocketlarder invite --revoke <name>
  pocketlarder backup <path>
`

// Run is the pocketlarder command. It returns the exit code: 0 for success,
// 1 for failure and 2 for a usage error.
func Run(ctx context.Context, args []string, getenv func(string) string, stdout, stderr io.Writer) int {
	cmd, arg, ok := parseArgs(args)
	if !ok {
		fmt.Fprint(stderr, usage)
		return 2
	}

	dir := getenv("POCKETLARDER_DATA_DIR")
	if dir == "" {
		dir = "/data"
	}
	// openDB puts the path in a "file:" URI, where these would cut off or change its pragmas.
	if strings.ContainsAny(dir, "?#%") {
		fmt.Fprintln(stderr, "pocketlarder: POCKETLARDER_DATA_DIR must not contain ?, # or %")
		return 1
	}
	var publicURL string
	if cmd != "backup" {
		if publicURL, ok = checkPublicURL(getenv("POCKETLARDER_PUBLIC_URL")); !ok {
			fmt.Fprintln(stderr, "pocketlarder: POCKETLARDER_PUBLIC_URL must be https://host[:port], http://localhost[:port] or http://127.0.0.1[:port]")
			return 1
		}
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	// Created 0600 first because SQLite gives the -wal and -shm files the database file's mode.
	path := filepath.Join(dir, "pocketlarder.db")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	f.Close()
	db, err := openDB(path)
	if err != nil {
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	defer db.Close()

	switch cmd {
	case "serve":
		listen := getenv("POCKETLARDER_LISTEN")
		if listen == "" {
			listen = ":8080"
		}
		return serve(ctx, db, publicURL, listen, stdout, stderr)
	case "backup":
		return backup(db, arg, stderr)
	}
	return invite(db, cmd, arg, publicURL, stdout, stderr)
}

// parseArgs accepts only the forms in usage. cmd is "serve", "backup",
// "invite", "--new-admin" or "--revoke".
func parseArgs(args []string) (cmd, arg string, ok bool) {
	switch {
	case len(args) == 1 && args[0] == "serve":
		return "serve", "", true
	case len(args) == 2 && args[0] == "backup":
		return "backup", args[1], true
	case len(args) == 2 && args[0] == "invite" && args[1] != "--new-admin" && args[1] != "--revoke":
		return "invite", args[1], true
	case len(args) == 3 && args[0] == "invite" && (args[1] == "--new-admin" || args[1] == "--revoke"):
		return args[1], args[2], true
	}
	return "", "", false
}

// checkPublicURL returns the URL as scheme://host[:port], so a trailing "/" is dropped.
func checkPublicURL(s string) (string, bool) {
	u, err := url.Parse(s)
	// ContainsAny also catches an empty query or fragment, which url.Parse doesn't keep.
	if err != nil || u.Hostname() == "" || u.User != nil || (u.Path != "" && u.Path != "/") || strings.ContainsAny(s, "?#") {
		return "", false
	}
	local := u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1"
	if u.Scheme != "https" && !(u.Scheme == "http" && local) {
		return "", false
	}
	return u.Scheme + "://" + u.Host, true
}

func serve(ctx context.Context, db *sql.DB, publicURL, listen string, stdout, stderr io.Writer) int {
	srv := &http.Server{
		Addr:              listen,
		Handler:           newServer(db, publicURL, slog.New(slog.NewJSONHandler(stdout, nil))).routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	failed := make(chan error, 1)
	go func() { failed <- srv.ListenAndServe() }()
	select {
	case err := <-failed:
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	return 0
}

// invite prints the code only after the commit, and never to stderr.
func invite(db *sql.DB, cmd, name, publicURL string, stdout, stderr io.Writer) int {
	var stored, code string
	var expires time.Time
	var revoked int
	err := withTx(db, func(tx *sql.Tx) (err error) {
		now := time.Now()
		var id string
		if cmd == "--new-admin" {
			id, err = createMember(tx, name, true, now)
		} else {
			id, err = memberByName(tx, name)
		}
		if err != nil {
			return err
		}
		if cmd == "--revoke" {
			revoked, err = revokeInvites(tx, id)
		} else {
			code, expires, err = createInvite(tx, id, now)
		}
		if err != nil {
			return err
		}
		return tx.QueryRow("SELECT name FROM members WHERE id = ?", id).Scan(&stored)
	})
	switch {
	case errors.Is(err, errNotFound):
		fmt.Fprintf(stderr, "pocketlarder: no member named %q\n", name)
		return 1
	case errors.Is(err, errConflict):
		fmt.Fprintf(stderr, "pocketlarder: a member named %q already exists\n", name)
		return 1
	case errors.Is(err, errInvalid):
		fmt.Fprintf(stderr, "pocketlarder: %q is not a valid member name\n", name)
		return 1
	case err != nil:
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	if cmd == "--revoke" {
		fmt.Fprintf(stdout, "Revoked %d invite(s) for %s.\n", revoked, stored)
		return 0
	}
	fmt.Fprintf(stdout, "Invite for %s, valid until %s:\n%s\n", stored, expires.UTC().Format(time.RFC3339), inviteURL(publicURL, code))
	return 0
}

// backup creates the target 0600 before VACUUM INTO fills it, so the umask
// can't make it readable to others. It never overwrites an existing file.
func backup(db *sql.DB, path string, stderr io.Writer) int {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	f.Close()
	if _, err := db.Exec("VACUUM INTO ?", path); err != nil {
		os.Remove(path)
		fmt.Fprintln(stderr, "pocketlarder:", err)
		return 1
	}
	return 0
}
