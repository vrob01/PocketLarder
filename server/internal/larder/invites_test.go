package larder

import (
	"database/sql"
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"
)

type listedInvite struct {
	ID        string `json:"id"`
	State     string `json:"state"`
	ExpiresAt string `json:"expires_at"`
}

// listInvites gets path, wants 200 and returns the invites, checking that each object has exactly the three keys.
func (e *testEnv) listInvites(path, token string) []listedInvite {
	e.t.Helper()
	w := e.call("GET", path, token, nil)
	var raw struct{ Invites []map[string]any }
	e.decode(w, http.StatusOK, &raw)
	for _, i := range raw.Invites {
		if len(i) != 3 || i["id"] == nil || i["state"] == nil || i["expires_at"] == nil {
			e.t.Errorf("invite %v, want exactly id, state and expires_at", i)
		}
	}
	var got struct{ Invites []listedInvite }
	e.decode(w, http.StatusOK, &got)
	return got.Invites
}

// inviteAt creates an invite for memberID as the CLI would at createdAt, which then expires 24 hours later.
func (e *testEnv) inviteAt(memberID string, createdAt time.Time) string {
	e.t.Helper()
	var code string
	err := withTx(e.db, func(tx *sql.Tx) (err error) {
		code, _, err = createInvite(tx, memberID, nil, createdAt)
		return err
	})
	if err != nil {
		e.t.Fatal(err)
	}
	return code
}

// redeemToken redeems code over HTTP and returns the new device's token.
func (e *testEnv) redeemToken(code string) string {
	e.t.Helper()
	var resp struct {
		Token string `json:"token"`
	}
	e.decode(e.call("POST", "/v1/invites/redeem", "", redeemBody(code)), http.StatusOK, &resp)
	return resp.Token
}

// inviteExists reports whether the invite row of code is still in the table.
func (e *testEnv) inviteExists(code string) bool {
	e.t.Helper()
	id, _, _ := strings.Cut(code, ".")
	var n int
	if err := e.db.QueryRow("SELECT count(*) FROM invites WHERE id = ?", id).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n == 1
}

func inviteID(code string) string {
	id, _, _ := strings.Cut(code, ".")
	return id
}

func expiry(createdAt time.Time) string {
	return createdAt.Add(24 * time.Hour).UTC().Format(time.RFC3339)
}

func TestListInvites(t *testing.T) {
	e := newTestEnv(t)
	_, admin := e.member("Alex", true)
	var sam, kim string
	err := withTx(e.db, func(tx *sql.Tx) error {
		sam = mustCreateMember(t, tx, "Sam", false)
		kim = mustCreateMember(t, tx, "Kim", false)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	redeemed := e.inviteAt(sam, testNow)
	user := e.redeemToken(redeemed)
	boundary := e.inviteAt(sam, testNow.Add(-23*time.Hour)) // expires exactly when the list is asked for
	expired := e.inviteAt(sam, testNow.Add(-25*time.Hour))
	e.now = testNow.Add(time.Hour)
	_, open := e.invite(user, map[string]any{})

	want := []listedInvite{
		{inviteID(open), "open", expiry(e.now)},
		{inviteID(redeemed), "redeemed", expiry(testNow)},
		{inviteID(boundary), "expired", expiry(testNow.Add(-23 * time.Hour))},
		{inviteID(expired), "expired", expiry(testNow.Add(-25 * time.Hour))},
	}
	if got := e.listInvites("/v1/invites", user); !reflect.DeepEqual(got, want) {
		t.Errorf("Sam's invites = %+v\nwant %+v", got, want)
	}

	// The list never carries a secret or an invite URL.
	body := e.call("GET", "/v1/invites", user, nil).Body.String()
	for _, code := range []string{open, redeemed, boundary, expired} {
		_, secret, _ := strings.Cut(code, ".")
		if strings.Contains(body, secret) {
			t.Errorf("the list holds the secret of %s: %s", inviteID(code), body)
		}
	}
	if strings.Contains(body, "pocketlarder://") {
		t.Errorf("the list holds an invite URL: %s", body)
	}

	if got := e.listInvites("/v1/invites?member_id="+sam, admin); !reflect.DeepEqual(got, want) {
		t.Errorf("Sam's invites for the admin = %+v\nwant %+v", got, want)
	}
	w := e.call("GET", "/v1/invites?member_id="+kim, admin, nil)
	if body := strings.TrimSpace(w.Body.String()); w.Code != http.StatusOK || body != `{"invites":[]}` {
		t.Errorf("Kim's invites: %d %s, want 200 {\"invites\":[]}", w.Code, body)
	}
}

func TestListInvitesPermissions(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	sam, user := e.member("Sam", false)
	for _, id := range []string{sam, alex, "", newID()} {
		e.wantError(e.call("GET", "/v1/invites?member_id="+id, user, nil), http.StatusForbidden, "forbidden")
	}
	if got := e.listInvites("/v1/invites?member_id="+sam, admin); len(got) != 1 || got[0].State != "redeemed" {
		t.Errorf("Sam's invites for the admin = %+v, want one redeemed", got)
	}
	for _, id := range []string{newID(), "not-a-uuid", ""} {
		e.wantError(e.call("GET", "/v1/invites?member_id="+id, admin, nil), http.StatusNotFound, "not_found")
	}
}

func TestCancelInvite(t *testing.T) {
	e := newTestEnv(t)
	sam, user := e.member("Sam", false)
	_, first := e.invite(user, map[string]any{})
	_, second := e.invite(user, map[string]any{})
	expired := e.inviteAt(sam, testNow.Add(-25*time.Hour))

	w := e.call("DELETE", "/v1/invites/"+inviteID(first), user, nil)
	if w.Code != http.StatusNoContent || w.Body.Len() != 0 {
		t.Errorf("cancel: %d %q, want 204 with no body", w.Code, w.Body)
	}
	e.wantError(e.call("POST", "/v1/invites/redeem", "", redeemBody(first)), http.StatusUnauthorized, "invalid_invite")
	e.wantStatus(e.call("DELETE", "/v1/invites/"+inviteID(expired), user, nil), http.StatusNoContent)
	if e.inviteExists(expired) {
		t.Error("the expired invite is still there")
	}
	e.wantStatus(e.call("POST", "/v1/invites/redeem", "", redeemBody(second)), http.StatusOK)
}

func TestCreatedInviteIDCancelsOnlyThatInvite(t *testing.T) {
	e := newTestEnv(t)
	_, user := e.member("Sam", false)
	first, firstCode := e.invite(user, map[string]any{})
	_, second := e.invite(user, map[string]any{})

	if first.ID == "" || first.ID != inviteID(firstCode) {
		t.Errorf("id = %q, want %q, the id part of the code", first.ID, inviteID(firstCode))
	}
	e.wantStatus(e.call("DELETE", "/v1/invites/"+first.ID, user, nil), http.StatusNoContent)
	e.wantStatus(e.call("POST", "/v1/invites/redeem", "", redeemBody(second)), http.StatusOK)
}

func TestCancelInviteRefusals(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	_, user := e.member("Sam", false)
	redeemed := e.inviteAt(alex, testNow)
	e.redeemToken(redeemed)
	_, alexOpen := e.invite(admin, map[string]any{})
	_, samOpen := e.invite(user, map[string]any{})

	e.wantError(e.call("DELETE", "/v1/invites/"+inviteID(redeemed), admin, nil), http.StatusConflict, "invite_redeemed")
	e.wantError(e.call("DELETE", "/v1/invites/"+newID(), user, nil), http.StatusNotFound, "not_found")
	e.wantError(e.call("DELETE", "/v1/invites/not-a-uuid", user, nil), http.StatusNotFound, "not_found")
	// Another member's invite looks unknown to a non-admin, redeemed or not.
	for _, code := range []string{alexOpen, redeemed} {
		e.wantError(e.call("DELETE", "/v1/invites/"+inviteID(code), user, nil), http.StatusNotFound, "not_found")
	}
	for _, code := range []string{redeemed, alexOpen, samOpen} {
		if !e.inviteExists(code) {
			t.Errorf("invite %s was deleted", inviteID(code))
		}
	}
	e.wantStatus(e.call("DELETE", "/v1/invites/"+inviteID(samOpen), admin, nil), http.StatusNoContent)
	if e.inviteExists(samOpen) {
		t.Error("the admin's cancel left Sam's invite")
	}
}

func TestClearInvites(t *testing.T) {
	e := newTestEnv(t)
	_, admin := e.member("Alex", true)
	sam, first := e.member("Sam", false) // one redeemed
	e.inviteAt(sam, testNow.Add(-25*time.Hour))
	e.inviteAt(sam, testNow.Add(-24*time.Hour)) // expires exactly now
	_, open := e.invite(first, map[string]any{})
	_, alsoOpen := e.invite(first, map[string]any{})

	var cleared struct {
		Cleared int `json:"cleared"`
	}
	e.decode(e.call("POST", "/v1/invites/clear", first, map[string]any{}), http.StatusOK, &cleared)
	if cleared.Cleared != 3 {
		t.Errorf("cleared %d, want 3", cleared.Cleared)
	}
	if got := e.listInvites("/v1/invites", first); len(got) != 2 || got[0].State != "open" || got[1].State != "open" {
		t.Errorf("Sam's invites after clearing = %+v, want two open", got)
	}
	// The device that paired through the cleared invite stays signed in.
	e.wantStatus(e.call("POST", "/v1/sync", first, map[string]any{"ops": []any{}}), http.StatusOK)
	e.redeemToken(open)
	if !e.inviteExists(alsoOpen) {
		t.Error("the other open invite is gone")
	}
	e.decode(e.call("POST", "/v1/invites/clear", admin, map[string]any{}), http.StatusOK, &cleared)
	if cleared.Cleared != 1 {
		t.Errorf("Alex cleared %d, want his 1 redeemed", cleared.Cleared)
	}
}

func TestClearInvitesRefusals(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	sam, user := e.member("Sam", false)
	e.wantError(e.call("POST", "/v1/invites/clear", user, map[string]string{"member_id": alex}), http.StatusForbidden, "forbidden")
	e.wantError(e.call("POST", "/v1/invites/clear", user, map[string]string{"member_id": sam}), http.StatusForbidden, "forbidden")
	if n := len(e.listInvites("/v1/invites?member_id="+alex, admin)); n != 1 {
		t.Errorf("Alex has %d invites after the refusal, want 1", n)
	}
	e.wantError(e.call("POST", "/v1/invites/clear", admin, map[string]string{"member_id": newID()}), http.StatusNotFound, "not_found")

	// Alex's clear is authenticated, then he loses admin rights before its body arrives.
	w := e.callHooked(func() {
		if _, err := e.db.Exec("UPDATE members SET is_admin = 0 WHERE id = ?", alex); err != nil {
			t.Error(err)
		}
	}, "POST", "/v1/invites/clear", admin, map[string]string{"member_id": sam})
	e.wantError(w, http.StatusForbidden, "forbidden")
	if n := len(e.listInvites("/v1/invites", user)); n != 1 {
		t.Errorf("Sam has %d invites after the refused clear, want 1", n)
	}

	if _, err := e.db.Exec("UPDATE members SET is_admin = 1 WHERE id = ?", alex); err != nil {
		t.Fatal(err)
	}
	var cleared struct {
		Cleared int `json:"cleared"`
	}
	e.decode(e.call("POST", "/v1/invites/clear", admin, map[string]string{"member_id": sam}), http.StatusOK, &cleared)
	if n := len(e.listInvites("/v1/invites", user)); cleared.Cleared != 1 || n != 0 {
		t.Errorf("the admin cleared %d of Sam's invites, %d left; want 1, 0", cleared.Cleared, n)
	}
	if n := len(e.listInvites("/v1/invites", admin)); n != 1 {
		t.Errorf("Alex has %d invites after clearing Sam's, want 1", n)
	}
}
