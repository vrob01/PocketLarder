package larder

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"
)

type testEnv struct {
	t    *testing.T
	db   *sql.DB
	srv  *server
	h    http.Handler
	now  time.Time
	logs *bytes.Buffer
}

func newTestEnv(t *testing.T) *testEnv {
	e := &testEnv{t: t, db: testDB(t), now: testNow, logs: &bytes.Buffer{}}
	e.srv = newServer(e.db, "https://lists.example.test", slog.New(slog.NewTextHandler(e.logs, nil)))
	e.srv.now = func() time.Time { return e.now }
	e.h = e.srv.routes()
	return e
}

func (e *testEnv) call(method, path, token string, body any) *httptest.ResponseRecorder {
	e.t.Helper()
	var b bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&b).Encode(body); err != nil {
			e.t.Fatal(err)
		}
	}
	r := httptest.NewRequest(method, path, &b)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, r)
	return w
}

// member creates a member and an invite in the database, then redeems it over HTTP.
func (e *testEnv) member(name string, admin bool) (memberID, token string) {
	e.t.Helper()
	var code string
	err := withTx(e.db, func(tx *sql.Tx) (err error) {
		if memberID, err = createMember(tx, name, admin, e.now); err != nil {
			return err
		}
		code, _, err = createInvite(tx, memberID, e.now)
		return err
	})
	if err != nil {
		e.t.Fatal(err)
	}
	var resp struct {
		Token string `json:"token"`
	}
	e.decode(e.call("POST", "/v1/invites/redeem", "", map[string]string{"code": code, "device_name": "Phone"}), http.StatusOK, &resp)
	return memberID, resp.Token
}

// decode checks the status and decodes the body into v.
func (e *testEnv) decode(w *httptest.ResponseRecorder, status int, v any) {
	e.t.Helper()
	if w.Code != status {
		e.t.Fatalf("status %d %s, want %d", w.Code, w.Body, status)
	}
	if err := json.Unmarshal(w.Body.Bytes(), v); err != nil {
		e.t.Fatalf("decode %s: %v", w.Body, err)
	}
}

// wantError checks the status and the error code in the body.
func (e *testEnv) wantError(w *httptest.ResponseRecorder, status int, code string) {
	e.t.Helper()
	var body struct {
		Error string `json:"error"`
	}
	json.Unmarshal(w.Body.Bytes(), &body)
	if w.Code != status || body.Error != code {
		e.t.Errorf("got %d %s, want %d %q", w.Code, w.Body, status, code)
	}
}

func (e *testEnv) wantStatus(w *httptest.ResponseRecorder, status int) {
	e.t.Helper()
	if w.Code != status {
		e.t.Errorf("got %d %s, want %d", w.Code, w.Body, status)
	}
}

type inviteResponse struct {
	URL       string `json:"url"`
	ExpiresAt string `json:"expires_at"`
	MemberID  string `json:"member_id"`
}

// invite posts body to /v1/invites, wants 201 and returns the response and the code from its URL.
func (e *testEnv) invite(token string, body any) (inviteResponse, string) {
	e.t.Helper()
	var resp inviteResponse
	e.decode(e.call("POST", "/v1/invites", token, body), http.StatusCreated, &resp)
	_, code, _ := strings.Cut(resp.URL, "&code=")
	return resp, code
}

func redeemBody(code string) map[string]string {
	return map[string]string{"code": code, "device_name": "Phone"}
}

func TestRedeemThenSignOut(t *testing.T) {
	e := newTestEnv(t)
	var alex, code string
	err := withTx(e.db, func(tx *sql.Tx) error {
		alex = mustCreateMember(t, tx, "Alex", true)
		code = mustCreateInvite(t, tx, alex)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	w := e.call("POST", "/v1/invites/redeem", "", redeemBody(code))
	if ct, cc := w.Header().Get("Content-Type"), w.Header().Get("Cache-Control"); ct != "application/json" || cc != "no-store" {
		t.Errorf("Content-Type %q, Cache-Control %q; want application/json, no-store", ct, cc)
	}
	var resp struct {
		Token    string `json:"token"`
		MemberID string `json:"member_id"`
		DeviceID string `json:"device_id"`
	}
	e.decode(w, http.StatusOK, &resp)
	if resp.Token == "" || resp.MemberID != alex || !validID(resp.DeviceID) {
		t.Fatalf("redeem = %+v, want a token, member %s and a device id", resp, alex)
	}

	w = e.call("POST", "/v1/signout", resp.Token, nil)
	if w.Code != http.StatusNoContent || w.Body.Len() != 0 {
		t.Errorf("signout: %d %q, want 204 with no body", w.Code, w.Body)
	}
	e.wantError(e.call("POST", "/v1/signout", resp.Token, nil), http.StatusUnauthorized, "unauthorized")
}

func TestAuthRequired(t *testing.T) {
	e := newTestEnv(t)
	id := newID()
	for _, route := range []string{
		"POST /v1/invites",
		"POST /v1/invites/revoke",
		"POST /v1/signout",
		"GET /v1/admin/members",
		"PATCH /v1/admin/members/" + id,
		"DELETE /v1/admin/members/" + id,
		"DELETE /v1/admin/devices/" + id,
	} {
		method, path, _ := strings.Cut(route, " ")
		for _, token := range []string{"", "x.y"} {
			e.wantError(e.call(method, path, token, map[string]any{}), http.StatusUnauthorized, "unauthorized")
		}
	}

	// A valid token only counts with the Bearer scheme.
	_, token := e.member("Alex", true)
	r := httptest.NewRequest("GET", "/v1/admin/members", nil)
	r.Header.Set("Authorization", "Token "+token)
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, r)
	e.wantError(w, http.StatusUnauthorized, "unauthorized")
}

func TestRedeemRateLimited(t *testing.T) {
	e := newTestEnv(t)
	var code string
	err := withTx(e.db, func(tx *sql.Tx) error {
		code = mustCreateInvite(t, tx, mustCreateMember(t, tx, "Alex", true))
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	bogus := redeemBody(newID() + ".bogus")
	for range 10 {
		e.wantError(e.call("POST", "/v1/invites/redeem", "", bogus), http.StatusUnauthorized, "invalid_invite")
	}
	// The limit comes first, so even a valid code is refused.
	e.wantError(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusTooManyRequests, "rate_limited")
	e.wantError(e.call("POST", "/v1/invites/redeem", "", nil), http.StatusTooManyRequests, "rate_limited") // before the body is read

	e.now = e.now.Add(time.Minute)
	e.wantError(e.call("POST", "/v1/invites/redeem", "", bogus), http.StatusUnauthorized, "invalid_invite")
	e.wantStatus(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusOK)
}

func TestInvitePermissions(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	kim, user := e.member("Kim", false)

	own, _ := e.invite(user, map[string]any{})
	if !strings.HasPrefix(own.URL, "pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code=") {
		t.Errorf("url = %q", own.URL)
	}
	if want := e.now.Add(24 * time.Hour).UTC().Format(time.RFC3339); own.MemberID != kim || own.ExpiresAt != want {
		t.Errorf("own invite: member %s, expires %s; want %s, %s", own.MemberID, own.ExpiresAt, kim, want)
	}

	for _, body := range []map[string]string{{"new_member_name": "Sam"}, {"member_id": alex}, {"member_id": ""}, {"member_id": kim}} {
		e.wantError(e.call("POST", "/v1/invites", user, body), http.StatusForbidden, "forbidden")
	}

	sam, code := e.invite(admin, map[string]string{"new_member_name": "Sam"})
	var name string
	var isAdmin bool
	if err := e.db.QueryRow("SELECT name, is_admin FROM members WHERE id = ?", sam.MemberID).Scan(&name, &isAdmin); err != nil || name != "Sam" || isAdmin {
		t.Errorf("new member: %q, admin %v, %v; want Sam, not admin", name, isAdmin, err)
	}
	var redeemed struct {
		MemberID string `json:"member_id"`
	}
	e.decode(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusOK, &redeemed)
	if redeemed.MemberID != sam.MemberID {
		t.Errorf("Sam's invite redeemed for %s, want %s", redeemed.MemberID, sam.MemberID)
	}
	e.wantError(e.call("POST", "/v1/invites", admin, map[string]string{"new_member_name": "sam"}), http.StatusConflict, "conflict")
	e.wantError(e.call("POST", "/v1/invites", admin, map[string]string{"new_member_name": ""}), http.StatusBadRequest, "invalid")

	if forKim, _ := e.invite(admin, map[string]string{"member_id": kim}); forKim.MemberID != kim {
		t.Errorf("admin invite for Kim: member %s, want %s", forKim.MemberID, kim)
	}
	e.wantError(e.call("POST", "/v1/invites", admin, map[string]string{"member_id": kim, "new_member_name": "Robin"}), http.StatusBadRequest, "invalid")
	e.wantError(e.call("POST", "/v1/invites", admin, map[string]string{"member_id": newID()}), http.StatusNotFound, "not_found")
}

type listedDevice struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	CreatedAt  string `json:"created_at"`
	LastSeenAt string `json:"last_seen_at"`
}

type listedMember struct {
	ID             string         `json:"id"`
	Name           string         `json:"name"`
	IsAdmin        bool           `json:"is_admin"`
	Privacy        string         `json:"privacy"`
	PendingInvites int            `json:"pending_invites"`
	Devices        []listedDevice `json:"devices"`
}

func TestAdminMembers(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	sam, user := e.member("Sam", false) // one redeemed invite
	err := withTx(e.db, func(tx *sql.Tx) error {
		_, _, err := createInvite(tx, sam, e.now.Add(-25*time.Hour)) // one expired an hour ago
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	e.now = e.now.Add(time.Hour)
	e.invite(user, map[string]any{}) // one pending, and Sam's last request
	samSeen := e.now.Format(time.RFC3339)
	e.now = e.now.Add(time.Hour)

	var got struct{ Members []listedMember }
	e.decode(e.call("GET", "/v1/admin/members", admin, nil), http.StatusOK, &got)
	created := testNow.Format(time.RFC3339)
	want := []listedMember{
		{ID: alex, Name: "Alex", IsAdmin: true, Privacy: "open", PendingInvites: 0, Devices: []listedDevice{{Name: "Phone", CreatedAt: created, LastSeenAt: e.now.Format(time.RFC3339)}}},
		{ID: sam, Name: "Sam", IsAdmin: false, Privacy: "open", PendingInvites: 1, Devices: []listedDevice{{Name: "Phone", CreatedAt: created, LastSeenAt: samSeen}}},
	}
	if sam < alex {
		want[0], want[1] = want[1], want[0]
	}
	for _, m := range got.Members {
		for i := range m.Devices {
			if !validID(m.Devices[i].ID) {
				t.Errorf("device id %q", m.Devices[i].ID)
			}
			m.Devices[i].ID = ""
		}
	}
	if !reflect.DeepEqual(got.Members, want) {
		t.Errorf("members = %+v\nwant %+v", got.Members, want)
	}
	e.wantError(e.call("GET", "/v1/admin/members", user, nil), http.StatusForbidden, "forbidden")

	robin, _ := e.invite(admin, map[string]string{"new_member_name": "Robin"})
	w := e.call("GET", "/v1/admin/members", admin, nil)
	if !strings.Contains(w.Body.String(), `"devices":[]`) {
		t.Errorf(`no "devices":[] in %s`, w.Body)
	}
	e.decode(w, http.StatusOK, &got)
	i := slices.IndexFunc(got.Members, func(m listedMember) bool { return m.ID == robin.MemberID })
	if i < 0 || got.Members[i].Name != "Robin" || got.Members[i].PendingInvites != 1 || len(got.Members[i].Devices) != 0 {
		t.Errorf("Robin missing or wrong in %s", w.Body)
	}
}

func TestHTTPRevokeInvites(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	sam, user := e.member("Sam", false)

	_, code := e.invite(user, map[string]any{})
	var revoked struct {
		Revoked int `json:"revoked"`
	}
	e.decode(e.call("POST", "/v1/invites/revoke", user, map[string]any{}), http.StatusOK, &revoked)
	if revoked.Revoked != 1 {
		t.Errorf("revoked %d, want 1", revoked.Revoked)
	}
	e.wantError(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusUnauthorized, "invalid_invite")

	e.wantError(e.call("POST", "/v1/invites/revoke", user, map[string]string{"member_id": alex}), http.StatusForbidden, "forbidden")
	_, code = e.invite(user, map[string]any{})
	e.decode(e.call("POST", "/v1/invites/revoke", admin, map[string]string{"member_id": sam}), http.StatusOK, &revoked)
	if revoked.Revoked != 1 {
		t.Errorf("admin revoked %d of Sam's invites, want 1", revoked.Revoked)
	}
	e.wantError(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusUnauthorized, "invalid_invite")
	e.wantError(e.call("POST", "/v1/invites/revoke", admin, map[string]string{"member_id": newID()}), http.StatusNotFound, "not_found")

	// Revoking invites leaves paired devices signed in.
	e.wantStatus(e.call("POST", "/v1/invites/revoke", user, map[string]any{}), http.StatusOK)
}

func TestHTTPLastAdminGuard(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	e.wantError(e.call("PATCH", "/v1/admin/members/"+alex, admin, map[string]bool{"is_admin": false}), http.StatusConflict, "last_admin")
	e.wantError(e.call("DELETE", "/v1/admin/members/"+alex, admin, nil), http.StatusConflict, "last_admin")
	e.wantError(e.call("PATCH", "/v1/admin/members/not-a-uuid", admin, map[string]bool{"is_admin": true}), http.StatusNotFound, "not_found")
	e.wantError(e.call("DELETE", "/v1/admin/members/not-a-uuid", admin, nil), http.StatusNotFound, "not_found")
	e.wantError(e.call("PATCH", "/v1/admin/members/"+alex, admin, map[string]any{}), http.StatusBadRequest, "invalid")
	e.wantError(e.call("PATCH", "/v1/admin/members/"+newID(), admin, map[string]bool{"is_admin": true}), http.StatusNotFound, "not_found")

	// With a second admin, Alex can step down, and Sam can remove him.
	sam, samToken := e.member("Sam", false)
	e.wantStatus(e.call("PATCH", "/v1/admin/members/"+sam, admin, map[string]bool{"is_admin": true}), http.StatusNoContent)
	e.wantStatus(e.call("PATCH", "/v1/admin/members/"+alex, admin, map[string]bool{"is_admin": false}), http.StatusNoContent)
	e.wantError(e.call("GET", "/v1/admin/members", admin, nil), http.StatusForbidden, "forbidden")
	e.wantStatus(e.call("DELETE", "/v1/admin/members/"+alex, samToken, nil), http.StatusNoContent)
	e.wantError(e.call("POST", "/v1/invites/revoke", admin, map[string]any{}), http.StatusUnauthorized, "unauthorized")
	e.wantError(e.call("DELETE", "/v1/admin/members/"+sam, samToken, nil), http.StatusConflict, "last_admin")
}

func TestRevokeDevice(t *testing.T) {
	e := newTestEnv(t)
	_, admin := e.member("Alex", true)
	_, user := e.member("Sam", false)
	device, _, _ := strings.Cut(user, ".")

	e.wantError(e.call("DELETE", "/v1/admin/devices/"+device, user, nil), http.StatusForbidden, "forbidden")
	e.wantStatus(e.call("DELETE", "/v1/admin/devices/"+device, admin, nil), http.StatusNoContent)
	e.wantError(e.call("POST", "/v1/invites/revoke", user, map[string]any{}), http.StatusUnauthorized, "unauthorized")
	e.wantError(e.call("DELETE", "/v1/admin/devices/"+device, admin, nil), http.StatusNotFound, "not_found")
	e.wantError(e.call("DELETE", "/v1/admin/devices/not-a-uuid", admin, nil), http.StatusNotFound, "not_found")
}

func TestSecretsNeverLogged(t *testing.T) {
	e := newTestEnv(t)
	var code string
	err := withTx(e.db, func(tx *sql.Tx) error {
		code = mustCreateInvite(t, tx, mustCreateMember(t, tx, "Alex", true))
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	var resp struct {
		Token string `json:"token"`
	}
	e.decode(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusOK, &resp)
	device, _, _ := strings.Cut(resp.Token, ".")
	other, _ := newSecret()
	wrong := device + "." + other
	e.wantError(e.call("GET", "/v1/admin/members", wrong, nil), http.StatusUnauthorized, "unauthorized")
	_, created := e.invite(resp.Token, map[string]any{})
	e.db.Close() // a database failure logs the error, not the request
	e.wantError(e.call("POST", "/v1/invites/redeem", "", redeemBody(created)), http.StatusInternalServerError, "internal")

	logs := e.logs.String()
	if !strings.Contains(logs, "/v1/invites/redeem") || !strings.Contains(logs, "database is closed") {
		t.Fatalf("requests or the database failure not logged:\n%s", logs)
	}
	for _, secret := range []string{code, resp.Token, wrong, created} {
		_, part, _ := strings.Cut(secret, ".")
		if strings.Contains(logs, secret) || strings.Contains(logs, part) {
			t.Errorf("logs contain the secret %q:\n%s", secret, logs)
		}
	}
}

func TestBodyLimits(t *testing.T) {
	e := newTestEnv(t)
	_, token := e.member("Alex", true)
	big := map[string]string{"code": strings.Repeat("x", 100<<10)}

	w := e.call("POST", "/v1/invites/redeem", "", big)
	if body := strings.TrimSpace(w.Body.String()); w.Code != http.StatusRequestEntityTooLarge || body != `{"error":"too_large"}` {
		t.Errorf("100 KiB redeem: %d %s, want 413", w.Code, body)
	}
	w = e.call("POST", "/v1/invites/redeem", "", map[string]string{"code": "x", "device_name": "Phone", "extra": "y"})
	if body := strings.TrimSpace(w.Body.String()); w.Code != http.StatusBadRequest || body != `{"error":"invalid"}` {
		t.Errorf("unknown field: %d %s, want 400", w.Code, body)
	}
	e.wantError(e.call("POST", "/v1/invites/redeem", "", nil), http.StatusBadRequest, "invalid")
	e.wantError(e.call("POST", "/v1/invites/redeem", "", map[string]int{"code": 1}), http.StatusBadRequest, "invalid")
	e.wantError(e.call("POST", "/v1/invites", token, big), http.StatusRequestEntityTooLarge, "too_large")
}
