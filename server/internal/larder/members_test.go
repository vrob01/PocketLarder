package larder

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"errors"
	"strings"
	"testing"
	"time"
)

// testTx opens a transaction on a fresh database. Query through it, not the
// database: with one connection, a query outside the open tx waits forever.
func testTx(t *testing.T) *sql.Tx {
	t.Helper()
	tx, err := testDB(t).Begin()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { tx.Rollback() })
	return tx
}

var testNow = time.Date(2026, 10, 27, 10, 0, 0, 0, time.UTC)

func mustCreateMember(t *testing.T, tx *sql.Tx, name string, admin bool) string {
	t.Helper()
	id, err := createMember(tx, name, admin, testNow)
	if err != nil {
		t.Fatalf("createMember(%q): %v", name, err)
	}
	return id
}

func mustCreateInvite(t *testing.T, tx *sql.Tx, memberID string) string {
	t.Helper()
	code, expires, err := createInvite(tx, memberID, testNow)
	if err != nil {
		t.Fatalf("createInvite: %v", err)
	}
	if want := testNow.Add(24 * time.Hour); !expires.Equal(want) {
		t.Fatalf("invite expires %v, want %v", expires, want)
	}
	return code
}

func mustRedeemInvite(t *testing.T, tx *sql.Tx, code string, now time.Time) (string, device) {
	t.Helper()
	token, d, err := redeemInvite(tx, code, "Phone", now)
	if err != nil {
		t.Fatalf("redeemInvite: %v", err)
	}
	return token, d
}

// secretSHA returns the SHA-256 of the secret part of an invite code or device token.
func secretSHA(code string) []byte {
	_, secret, _ := strings.Cut(code, ".")
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

func storedHash(t *testing.T, tx *sql.Tx, table, code string) []byte {
	t.Helper()
	id, _, _ := strings.Cut(code, ".")
	var hash []byte
	if err := tx.QueryRow("SELECT secret_hash FROM "+table+" WHERE id = ?", id).Scan(&hash); err != nil {
		t.Fatalf("%s %s: %v", table, id, err)
	}
	return hash
}

func TestInviteRedeemsOnceAndStoresOnlyHash(t *testing.T) {
	tx := testTx(t)
	alex := mustCreateMember(t, tx, "Alex", true)
	code := mustCreateInvite(t, tx, alex)
	if !bytes.Equal(storedHash(t, tx, "invites", code), secretSHA(code)) {
		t.Error("invites.secret_hash is not the SHA-256 of the code's secret")
	}

	for _, name := range []string{strings.Repeat("x", 65), "Phone\u202e"} {
		if _, _, err := redeemInvite(tx, code, name, testNow); err != errInvalid {
			t.Fatalf("redeem with device name %q: %v, want errInvalid", name, err)
		}
	}
	token, d := mustRedeemInvite(t, tx, code, testNow)
	if d.MemberID != alex || !d.IsAdmin {
		t.Errorf("device = %+v, want member %s and admin", d, alex)
	}
	if !bytes.Equal(storedHash(t, tx, "devices", token), secretSHA(token)) {
		t.Error("devices.secret_hash is not the SHA-256 of the token's secret")
	}
	if _, _, err := redeemInvite(tx, code, "Phone", testNow); err != errBadInvite {
		t.Errorf("second redemption: %v, want errBadInvite", err)
	}

	_, d, err := redeemInvite(tx, mustCreateInvite(t, tx, alex), " \t ", testNow)
	if err != nil {
		t.Fatal(err)
	}
	var name string
	if err := tx.QueryRow("SELECT name FROM devices WHERE id = ?", d.ID).Scan(&name); err != nil {
		t.Fatal(err)
	}
	if name != "Unnamed device" {
		t.Errorf("whitespace-only device name stored as %q, want %q", name, "Unnamed device")
	}

	if _, _, err := createInvite(tx, newID(), testNow); err != errNotFound {
		t.Errorf("createInvite for an unknown member: %v, want errNotFound", err)
	}
	want := "pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code=" + code
	if got := inviteURL("https://lists.example.test", code); got != want {
		t.Errorf("inviteURL = %q, want %q", got, want)
	}
}

func TestInviteExpiry(t *testing.T) {
	tx := testTx(t)
	alex := mustCreateMember(t, tx, "Alex", true)
	mustRedeemInvite(t, tx, mustCreateInvite(t, tx, alex), testNow.Add(23*time.Hour+59*time.Minute))
	late := testNow.Add(24*time.Hour + time.Second)
	if _, _, err := redeemInvite(tx, mustCreateInvite(t, tx, alex), "Phone", late); err != errBadInvite {
		t.Errorf("redeem after 24h: %v, want errBadInvite", err)
	}
}

func TestInviteWrongSecret(t *testing.T) {
	tx := testTx(t)
	alex := mustCreateMember(t, tx, "Alex", true)
	id, _, _ := strings.Cut(mustCreateInvite(t, tx, alex), ".")
	other, _ := newSecret()
	if _, _, err := redeemInvite(tx, id+"."+other, "Phone", testNow); err != errBadInvite {
		t.Errorf("redeem with a wrong secret: %v, want errBadInvite", err)
	}
}

func TestAuthenticate(t *testing.T) {
	tx := testTx(t)
	alex := mustCreateMember(t, tx, "Alex", true)
	token, redeemed := mustRedeemInvite(t, tx, mustCreateInvite(t, tx, alex), testNow)

	later := testNow.Add(time.Hour)
	d, err := authenticate(tx, token, later)
	if err != nil || d != redeemed {
		t.Fatalf("authenticate = %+v, %v; want %+v", d, err, redeemed)
	}
	var lastSeen int64
	if err := tx.QueryRow("SELECT last_seen_at FROM devices WHERE id = ?", d.ID).Scan(&lastSeen); err != nil {
		t.Fatal(err)
	}
	if lastSeen != later.Unix() {
		t.Errorf("last_seen_at = %d, want %d", lastSeen, later.Unix())
	}

	altered := token[:len(token)-1] + "A"
	if strings.HasSuffix(token, "A") {
		altered = token[:len(token)-1] + "B"
	}
	for _, bad := range []string{altered, "garbage"} {
		if _, err := authenticate(tx, bad, later); err != errUnauthorized {
			t.Errorf("authenticate(%q): %v, want errUnauthorized", bad, err)
		}
	}

	if err := deleteDevice(tx, d.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := authenticate(tx, token, later); err != errUnauthorized {
		t.Errorf("authenticate after deleteDevice: %v, want errUnauthorized", err)
	}
	if err := deleteDevice(tx, d.ID); err != errNotFound {
		t.Errorf("second deleteDevice: %v, want errNotFound", err)
	}
}

func TestRemoveMemberRevokesDevicesAndPersonalList(t *testing.T) {
	tx := testTx(t)
	mustCreateMember(t, tx, "Alex", true)
	sam := mustCreateMember(t, tx, "Sam", true)
	var list string
	if err := tx.QueryRow("SELECT id FROM lists WHERE owner_id = ?", sam).Scan(&list); err != nil {
		t.Fatal(err)
	}
	var lists int
	if err := tx.QueryRow("SELECT count(*) FROM lists WHERE owner_id = ?", sam).Scan(&lists); err != nil {
		t.Fatal(err)
	}
	if lists != 1 {
		t.Fatalf("Sam owns %d lists before removal, want 1", lists)
	}

	token, _ := mustRedeemInvite(t, tx, mustCreateInvite(t, tx, sam), testNow)
	if _, err := tx.Exec("INSERT INTO entries (id, list_id, text, created_at) VALUES (?, ?, 'Milk', ?)", newID(), list, testNow.Unix()); err != nil {
		t.Fatal(err)
	}

	if err := removeMember(tx, sam); err != nil {
		t.Fatal(err)
	}
	if _, err := authenticate(tx, token, testNow); err != errUnauthorized {
		t.Errorf("Sam's token after removal: %v, want errUnauthorized", err)
	}
	if err := tx.QueryRow("SELECT count(*) FROM lists WHERE owner_id = ?", sam).Scan(&lists); err != nil {
		t.Fatal(err)
	}
	if lists != 0 {
		t.Errorf("Sam still owns %d lists, want 0", lists)
	}
	var entries int
	if err := tx.QueryRow("SELECT count(*) FROM entries WHERE list_id = ?", list).Scan(&entries); err != nil {
		t.Fatal(err)
	}
	if entries != 0 {
		t.Errorf("%d entries left on Sam's list, want 0", entries)
	}
}

func TestLastAdminGuard(t *testing.T) {
	tx := testTx(t)
	alex := mustCreateMember(t, tx, "Alex", true)
	sam := mustCreateMember(t, tx, "Sam", false)
	if err := setAdmin(tx, alex, false); err != errLastAdmin {
		t.Errorf("sole admin demotes self: %v, want errLastAdmin", err)
	}
	if err := removeMember(tx, alex); err != errLastAdmin {
		t.Errorf("sole admin removed: %v, want errLastAdmin", err)
	}
	if err := setAdmin(tx, sam, true); err != nil {
		t.Fatal(err)
	}
	if err := setAdmin(tx, alex, false); err != nil {
		t.Errorf("demote with a second admin: %v, want nil", err)
	}
	unknown := newID()
	if err := setAdmin(tx, unknown, true); err != errNotFound {
		t.Errorf("setAdmin of an unknown member: %v, want errNotFound", err)
	}
	if err := removeMember(tx, unknown); err != errNotFound {
		t.Errorf("removeMember of an unknown member: %v, want errNotFound", err)
	}
}

func TestMemberNamesUniqueIgnoringCase(t *testing.T) {
	tx := testTx(t)
	alex := mustCreateMember(t, tx, "Alex", true)
	if _, err := createMember(tx, " alex ", false, testNow); !errors.Is(err, errConflict) {
		t.Errorf(`createMember(" alex "): %v, want errConflict`, err)
	}
	if _, err := createMember(tx, "   ", false, testNow); !errors.Is(err, errInvalid) {
		t.Errorf(`createMember("   "): %v, want errInvalid`, err)
	}
	if id, err := memberByName(tx, " ALEX "); err != nil || id != alex {
		t.Errorf(`memberByName(" ALEX ") = %q, %v; want %q`, id, err, alex)
	}
	if _, err := memberByName(tx, "Zed"); !errors.Is(err, errNotFound) {
		t.Errorf(`memberByName("Zed"): %v, want errNotFound`, err)
	}
}
