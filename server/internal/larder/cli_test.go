package larder

import (
	"bytes"
	"context"
	"database/sql"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// cliEnv is a fresh data dir and a valid public URL.
func cliEnv(t *testing.T) map[string]string {
	return map[string]string{
		"POCKETLARDER_DATA_DIR":   t.TempDir(),
		"POCKETLARDER_PUBLIC_URL": "https://lists.example.test",
	}
}

func runCLI(t *testing.T, env map[string]string, args ...string) (code int, stdout, stderr string) {
	t.Helper()
	var out, errOut bytes.Buffer
	code = Run(context.Background(), args, func(k string) string { return env[k] }, &out, &errOut)
	return code, out.String(), errOut.String()
}

// cliDB opens the database Run wrote; it is closed when the test ends.
func cliDB(t *testing.T, env map[string]string) *sql.DB {
	t.Helper()
	db, err := openDB(filepath.Join(env["POCKETLARDER_DATA_DIR"], "pocketlarder.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

// setUmask sets the process umask for the test and restores it afterwards.
func setUmask(t *testing.T, mask int) {
	old := syscall.Umask(mask)
	t.Cleanup(func() { syscall.Umask(old) })
}

func TestCLIInviteNewAdmin(t *testing.T) {
	env := cliEnv(t)
	code, stdout, stderr := runCLI(t, env, "invite", "--new-admin", "Alex")
	if code != 0 {
		t.Fatalf("exit %d, stderr %q", code, stderr)
	}
	lines := strings.Split(strings.TrimSuffix(stdout, "\n"), "\n")
	if len(lines) != 2 || !strings.HasPrefix(lines[0], "Invite for Alex, valid until ") ||
		!strings.HasPrefix(lines[1], "pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code=") {
		t.Fatalf("stdout %q", stdout)
	}
	until, err := time.Parse(time.RFC3339, strings.TrimSuffix(strings.TrimPrefix(lines[0], "Invite for Alex, valid until "), ":"))
	if err != nil || until.Location() != time.UTC || time.Until(until) < 23*time.Hour || time.Until(until) > 25*time.Hour {
		t.Fatalf("expiry in %q: %v", lines[0], err)
	}
	var admin bool
	if err := cliDB(t, env).QueryRow("SELECT is_admin FROM members WHERE name = 'Alex'").Scan(&admin); err != nil || !admin {
		t.Fatalf("Alex admin = %v, %v", admin, err)
	}
}

func TestCLIInviteExisting(t *testing.T) {
	env := cliEnv(t)
	if code, _, stderr := runCLI(t, env, "invite", "--new-admin", "Alex"); code != 0 {
		t.Fatalf("new admin: exit %d, stderr %q", code, stderr)
	}
	code, stdout, stderr := runCLI(t, env, "invite", "alex")
	if code != 0 || !strings.HasPrefix(stdout, "Invite for Alex, valid until ") {
		t.Fatalf("alex: exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	code, stdout, stderr = runCLI(t, env, "invite", "Zed")
	if code != 1 || stdout != "" || !strings.Contains(stderr, "Zed") {
		t.Fatalf("Zed: exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	if code, _, stderr := runCLI(t, env, "invite", "--new-admin", "alex"); code != 1 || stderr == "" {
		t.Fatalf("taken name: exit %d, stderr %q", code, stderr)
	}
}

func TestCLIInviteRevoke(t *testing.T) {
	env := cliEnv(t)
	if code, _, stderr := runCLI(t, env, "invite", "--new-admin", "Alex"); code != 0 {
		t.Fatalf("new admin: exit %d, stderr %q", code, stderr)
	}
	code, stdout, stderr := runCLI(t, env, "invite", "--revoke", "alex")
	if code != 0 || stdout != "Revoked 1 invite(s) for Alex.\n" {
		t.Fatalf("revoke: exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	var pending int
	if err := cliDB(t, env).QueryRow("SELECT count(*) FROM invites i JOIN members m ON m.id = i.member_id WHERE m.name = 'Alex' AND i.used_at IS NULL").Scan(&pending); err != nil || pending != 0 {
		t.Fatalf("pending invites = %d, %v", pending, err)
	}
	if code, _, stderr := runCLI(t, env, "invite", "--revoke", "Zed"); code != 1 || !strings.Contains(stderr, "Zed") {
		t.Fatalf("Zed: exit %d, stderr %q", code, stderr)
	}
}

func TestCLIPublicURL(t *testing.T) {
	for _, tc := range []struct {
		url  string
		code int
	}{
		{"", 1},
		{"http://lists.example.test", 1},
		{"https://lists.example.test/app", 1},
		{"https://lists.example.test?x=1", 1},
		{"https://lists.example.test/#", 1},
		{"https://user@lists.example.test", 1},
		{"lists.example.test", 1},
		{"http://localhost:5100", 0},
		{"http://127.0.0.1", 0},
		{"https://lists.example.test/", 0},
	} {
		env := cliEnv(t)
		env["POCKETLARDER_PUBLIC_URL"] = tc.url
		code, stdout, stderr := runCLI(t, env, "invite", "--new-admin", "Alex")
		if code != tc.code {
			t.Errorf("%q: exit %d, want %d, stderr %q", tc.url, code, tc.code, stderr)
		}
		if tc.code == 1 && !strings.Contains(stderr, "POCKETLARDER_PUBLIC_URL") {
			t.Errorf("%q: stderr %q does not name POCKETLARDER_PUBLIC_URL", tc.url, stderr)
		}
		if tc.url == "https://lists.example.test/" && !strings.Contains(stdout, "server=https%3A%2F%2Flists.example.test&code=") {
			t.Errorf("trailing slash kept: %q", stdout)
		}
	}
}

func TestCLIBackup(t *testing.T) {
	env := cliEnv(t)
	if code, _, stderr := runCLI(t, env, "invite", "--new-admin", "Alex"); code != 0 {
		t.Fatalf("new admin: exit %d, stderr %q", code, stderr)
	}
	target := filepath.Join(t.TempDir(), "b.db")
	if code, stdout, stderr := runCLI(t, env, "backup", target); code != 0 || stdout != "" {
		t.Fatalf("backup: exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	db, err := openDB(target)
	if err != nil {
		t.Fatal(err)
	}
	var name string
	err = db.QueryRow("SELECT name FROM members").Scan(&name)
	db.Close()
	if err != nil || name != "Alex" {
		t.Fatalf("backup has %q, %v", name, err)
	}

	before, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if code, _, _ := runCLI(t, env, "backup", target); code != 1 {
		t.Fatalf("backup onto an existing file: exit %d, want 1", code)
	}
	if after, err := os.ReadFile(target); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("existing backup changed: %v", err)
	}
}

func TestCLIBackupFileMode(t *testing.T) {
	setUmask(t, 0o022)
	env := cliEnv(t)
	if code, _, stderr := runCLI(t, env, "invite", "--new-admin", "Alex"); code != 0 {
		t.Fatalf("new admin: exit %d, stderr %q", code, stderr)
	}
	target := filepath.Join(t.TempDir(), "b.db")
	if code, _, stderr := runCLI(t, env, "backup", target); code != 0 {
		t.Fatalf("backup: exit %d, stderr %q", code, stderr)
	}
	info, err := os.Stat(target)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("backup mode %v, want 0600", info.Mode().Perm())
	}
}

func TestCLIDataDirRejectsURIChars(t *testing.T) {
	for _, name := range []string{"a?b", "a#b", "a%b"} {
		env := cliEnv(t)
		dir := filepath.Join(env["POCKETLARDER_DATA_DIR"], name)
		env["POCKETLARDER_DATA_DIR"] = dir
		code, _, stderr := runCLI(t, env, "invite", "--new-admin", "Alex")
		if code != 1 || !strings.Contains(stderr, "POCKETLARDER_DATA_DIR") {
			t.Errorf("%s: exit %d, stderr %q", name, code, stderr)
		}
		if _, err := os.Stat(dir); !os.IsNotExist(err) {
			t.Errorf("%s: created anyway (%v)", name, err)
		}
	}
}

func TestCLIFileModes(t *testing.T) {
	setUmask(t, 0o022)
	env := cliEnv(t)
	dir := filepath.Join(env["POCKETLARDER_DATA_DIR"], "data")
	env["POCKETLARDER_DATA_DIR"] = dir
	if code, _, stderr := runCLI(t, env, "invite", "--new-admin", "Alex"); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, stderr)
	}
	if info, err := os.Stat(dir); err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("data dir: %v, %v", info, err)
	}
	// Run closed the database, which removes -wal and -shm; an open one brings them back.
	db := cliDB(t, env)
	if _, err := db.Exec("UPDATE members SET privacy = 'open'"); err != nil {
		t.Fatal(err)
	}
	files, err := filepath.Glob(filepath.Join(dir, "pocketlarder.db*"))
	if err != nil || len(files) != 3 {
		t.Fatalf("database files %v, %v", files, err)
	}
	for _, f := range files {
		info, err := os.Stat(f)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Errorf("%s: mode %v, want 0600", f, info.Mode().Perm())
		}
	}
}

func TestServe(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := l.Addr().String()
	l.Close()
	env := cliEnv(t)
	env["POCKETLARDER_LISTEN"] = addr
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var logs, stderr bytes.Buffer
	done := make(chan int, 1)
	go func() { done <- Run(ctx, []string{"serve"}, func(k string) string { return env[k] }, &logs, &stderr) }()

	status := 0
	for deadline := time.Now().Add(2 * time.Second); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		resp, err := http.Post("http://"+addr+"/v1/sync", "application/json", strings.NewReader("{}"))
		if err == nil {
			status = resp.StatusCode
			resp.Body.Close()
			break
		}
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("POST /v1/sync = %d, want 401", status)
	}

	cancel()
	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("exit %d, stderr %q", code, stderr.String())
		}
	case <-time.After(5 * time.Second):
		t.Fatal("serve did not stop within 5s")
	}
	if !strings.Contains(logs.String(), `"pattern":"POST /v1/sync","status":401`) {
		t.Fatalf("log %q", logs.String())
	}
}

func TestUsage(t *testing.T) {
	// Fails the test if Run reads the environment, so the default /data is never touched.
	getenv := func(k string) string {
		t.Fatalf("read %s", k)
		return ""
	}
	for _, args := range [][]string{
		{},
		{"frobnicate"},
		{"serve", "extra"},
		{"invite"},
		{"invite", "--new-admin"},
		{"invite", "--revoke"},
		{"invite", "Alex", "Zed"},
		{"invite", "--new-admin", "Alex", "Zed"},
		{"backup"},
		{"backup", "a.db", "b.db"},
	} {
		var stdout, stderr bytes.Buffer
		if code := Run(context.Background(), args, getenv, &stdout, &stderr); code != 2 {
			t.Errorf("%q: exit %d, want 2", args, code)
		}
		if !strings.Contains(stderr.String(), "invite --new-admin <name>") || stdout.Len() != 0 {
			t.Errorf("%q: stdout %q, stderr %q", args, stdout.String(), stderr.String())
		}
	}
}
