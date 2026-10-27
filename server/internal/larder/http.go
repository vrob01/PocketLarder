package larder

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"
)

// maxBody caps every request body except sync's.
const maxBody = 64 << 10

type server struct {
	db          *sql.DB
	publicURL   string
	now         func() time.Time
	log         *slog.Logger
	redeemLimit *windowLimiter
}

func newServer(db *sql.DB, publicURL string, log *slog.Logger) *server {
	return &server{db: db, publicURL: publicURL, now: time.Now, log: log,
		redeemLimit: &windowLimiter{max: 10, window: time.Minute}}
}

// shortcut: one server-wide window, not per client IP, because codes are 256-bit; go per-IP if lockouts annoy
type windowLimiter struct {
	max    int
	window time.Duration
	start  time.Time
	n      int
	mu     sync.Mutex
}

func (l *windowLimiter) allow(now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if now.Sub(l.start) >= l.window {
		l.start, l.n = now, 0
	}
	if l.n >= l.max {
		return false
	}
	l.n++
	return true
}

// readJSON never logs or echoes the decoder's error, because it can quote the body.
func readJSON(w http.ResponseWriter, r *http.Request, limit int64, v any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, limit))
	dec.DisallowUnknownFields()
	err := dec.Decode(v)
	var tooLarge *http.MaxBytesError
	switch {
	case errors.As(err, &tooLarge):
		writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"error": "too_large"})
	case err != nil:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid"})
	}
	return err == nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

// errStatus maps each sentinel error to its status; the error's message is its code.
var errStatus = map[error]int{
	errInvalid:      http.StatusBadRequest,
	errUnauthorized: http.StatusUnauthorized,
	errBadInvite:    http.StatusUnauthorized,
	errForbidden:    http.StatusForbidden,
	errNotFound:     http.StatusNotFound,
	errConflict:     http.StatusConflict,
	errLastAdmin:    http.StatusConflict,
}

func (s *server) fail(w http.ResponseWriter, err error) {
	status, ok := errStatus[err]
	if !ok {
		s.log.Error("request failed", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal"})
		return
	}
	writeJSON(w, status, map[string]string{"error": err.Error()})
}

// authed commits the authentication before h runs: with one connection, h's
// own transaction would wait forever on an open one.
func (s *server) authed(adminOnly bool, h func(http.ResponseWriter, *http.Request, device)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			s.fail(w, errUnauthorized)
			return
		}
		var d device
		err := withTx(s.db, func(tx *sql.Tx) (err error) {
			d, err = authenticate(tx, token, s.now())
			return err
		})
		if err != nil {
			s.fail(w, err)
			return
		}
		if adminOnly && !d.IsAdmin {
			s.fail(w, errForbidden)
			return
		}
		h(w, r, d)
	}
}

// recheck re-reads the caller in the handler's transaction. A handler that
// reads a body waits on the client after authed has committed, and the device
// may be revoked or the member demoted meanwhile. Task 4's POST /v1/sync reads
// a body too and needs this.
func recheck(tx *sql.Tx, deviceID string, asAdmin bool) error {
	var isAdmin bool
	err := tx.QueryRow("SELECT m.is_admin FROM devices d JOIN members m ON m.id = d.member_id WHERE d.id = ?", deviceID).Scan(&isAdmin)
	if errors.Is(err, sql.ErrNoRows) {
		return errUnauthorized
	}
	if err != nil {
		return err
	}
	if asAdmin && !isAdmin {
		return errForbidden
	}
	return nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/invites/redeem", s.redeem)
	mux.HandleFunc("POST /v1/invites", s.authed(false, s.invite))
	mux.HandleFunc("POST /v1/invites/revoke", s.authed(false, s.revoke))
	mux.HandleFunc("POST /v1/signout", s.authed(false, s.signOut))
	mux.HandleFunc("GET /v1/admin/members", s.authed(true, s.members))
	mux.HandleFunc("PATCH /v1/admin/members/{id}", s.authed(true, s.patchMember))
	mux.HandleFunc("DELETE /v1/admin/members/{id}", s.authed(true, s.deleteMember))
	mux.HandleFunc("DELETE /v1/admin/devices/{id}", s.authed(true, s.revokeDevice))
	// The log line carries no path, query, header or body: they can hold ids and secrets.
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		mux.ServeHTTP(sw, r) // sets r.Pattern
		s.log.Info("request", "method", r.Method, "pattern", r.Pattern, "status", sw.status, "duration", time.Since(start))
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (s *server) redeem(w http.ResponseWriter, r *http.Request) {
	// Before anything else, so a 429 says nothing about the code.
	if !s.redeemLimit.allow(s.now()) {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "rate_limited"})
		return
	}
	var req struct {
		Code       string `json:"code"`
		DeviceName string `json:"device_name"`
	}
	if !readJSON(w, r, maxBody, &req) {
		return
	}
	var token string
	var d device
	err := withTx(s.db, func(tx *sql.Tx) (err error) {
		token, d, err = redeemInvite(tx, req.Code, req.DeviceName, s.now())
		return err
	})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"token": token, "member_id": d.MemberID, "device_id": d.ID})
}

// invite's fields are pointers because a field counts as given even when it is "".
func (s *server) invite(w http.ResponseWriter, r *http.Request, d device) {
	var req struct {
		MemberID      *string `json:"member_id"`
		NewMemberName *string `json:"new_member_name"`
	}
	if !readJSON(w, r, maxBody, &req) {
		return
	}
	if (req.MemberID != nil || req.NewMemberName != nil) && !d.IsAdmin {
		s.fail(w, errForbidden)
		return
	}
	if req.MemberID != nil && req.NewMemberName != nil {
		s.fail(w, errInvalid)
		return
	}
	memberID := d.MemberID
	if req.MemberID != nil {
		memberID = *req.MemberID
	}
	var code string
	var expires time.Time
	err := withTx(s.db, func(tx *sql.Tx) (err error) {
		if err = recheck(tx, d.ID, req.MemberID != nil || req.NewMemberName != nil); err != nil {
			return err
		}
		now := s.now()
		if req.NewMemberName != nil {
			if memberID, err = createMember(tx, *req.NewMemberName, false, now); err != nil {
				return err
			}
		}
		code, expires, err = createInvite(tx, memberID, now)
		return err
	})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{
		"url":        inviteURL(s.publicURL, code),
		"expires_at": expires.UTC().Format(time.RFC3339),
		"member_id":  memberID,
	})
}

func (s *server) revoke(w http.ResponseWriter, r *http.Request, d device) {
	var req struct {
		MemberID *string `json:"member_id"`
	}
	if !readJSON(w, r, maxBody, &req) {
		return
	}
	memberID := d.MemberID
	if req.MemberID != nil {
		if !d.IsAdmin {
			s.fail(w, errForbidden)
			return
		}
		memberID = *req.MemberID
	}
	var n int
	err := withTx(s.db, func(tx *sql.Tx) (err error) {
		if err = recheck(tx, d.ID, req.MemberID != nil); err != nil {
			return err
		}
		n, err = revokeInvites(tx, memberID)
		return err
	})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"revoked": n})
}

func (s *server) signOut(w http.ResponseWriter, r *http.Request, d device) {
	if err := withTx(s.db, func(tx *sql.Tx) error { return deleteDevice(tx, d.ID) }); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type adminDevice struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	CreatedAt  string `json:"created_at"`
	LastSeenAt string `json:"last_seen_at"`
}

type adminMember struct {
	ID             string        `json:"id"`
	Name           string        `json:"name"`
	IsAdmin        bool          `json:"is_admin"`
	Privacy        string        `json:"privacy"`
	PendingInvites int           `json:"pending_invites"`
	Devices        []adminDevice `json:"devices"`
}

func (s *server) members(w http.ResponseWriter, r *http.Request, d device) {
	members := []adminMember{}
	err := withTx(s.db, func(tx *sql.Tx) error {
		rows, err := tx.Query(`SELECT m.id, m.name, m.is_admin, m.privacy,
  (SELECT count(*) FROM invites i WHERE i.member_id = m.id AND i.used_at IS NULL AND i.expires_at > ?),
  d.id, d.name, d.created_at, d.last_seen_at
FROM members m LEFT JOIN devices d ON d.member_id = m.id
ORDER BY m.id, d.id`, s.now().Unix())
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var m adminMember
			var devID, devName sql.NullString
			var created, seen sql.NullInt64
			if err := rows.Scan(&m.ID, &m.Name, &m.IsAdmin, &m.Privacy, &m.PendingInvites, &devID, &devName, &created, &seen); err != nil {
				return err
			}
			if len(members) == 0 || members[len(members)-1].ID != m.ID {
				m.Devices = []adminDevice{}
				members = append(members, m)
			}
			if devID.Valid {
				last := &members[len(members)-1]
				last.Devices = append(last.Devices, adminDevice{devID.String, devName.String,
					time.Unix(created.Int64, 0).UTC().Format(time.RFC3339), time.Unix(seen.Int64, 0).UTC().Format(time.RFC3339)})
			}
		}
		return rows.Err()
	})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string][]adminMember{"members": members})
}

func (s *server) patchMember(w http.ResponseWriter, r *http.Request, d device) {
	id := r.PathValue("id")
	if !validID(id) {
		s.fail(w, errNotFound)
		return
	}
	var req struct {
		IsAdmin *bool `json:"is_admin"`
	}
	if !readJSON(w, r, maxBody, &req) {
		return
	}
	if req.IsAdmin == nil {
		s.fail(w, errInvalid)
		return
	}
	err := withTx(s.db, func(tx *sql.Tx) error {
		if err := recheck(tx, d.ID, true); err != nil {
			return err
		}
		return setAdmin(tx, id, *req.IsAdmin)
	})
	if err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) deleteMember(w http.ResponseWriter, r *http.Request, d device) {
	id := r.PathValue("id")
	if !validID(id) {
		s.fail(w, errNotFound)
		return
	}
	if err := withTx(s.db, func(tx *sql.Tx) error { return removeMember(tx, id) }); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) revokeDevice(w http.ResponseWriter, r *http.Request, d device) {
	id := r.PathValue("id")
	if !validID(id) {
		s.fail(w, errNotFound)
		return
	}
	if err := withTx(s.db, func(tx *sql.Tx) error { return deleteDevice(tx, id) }); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
