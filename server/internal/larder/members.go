package larder

import (
	"database/sql"
	"errors"
	"net/url"
	"time"
)

type device struct {
	ID, MemberID string
	IsAdmin      bool
}

// Each message is the API error code the client sees.
var (
	errInvalid        = errors.New("invalid")
	errForbidden      = errors.New("forbidden")
	errNotFound       = errors.New("not_found")
	errConflict       = errors.New("conflict")
	errLastAdmin      = errors.New("last_admin")
	errBadInvite      = errors.New("invalid_invite")
	errUnauthorized   = errors.New("unauthorized")
	errTooManyInvites = errors.New("too_many_invites")
	errInviteRedeemed = errors.New("invite_redeemed")
)

// maxOpenInvites caps a member's unredeemed, unexpired invites made through the API.
const maxOpenInvites = 10

// rowsChanged returns how many rows a statement changed.
func rowsChanged(res sql.Result, err error) (int64, error) {
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// createMember creates a member and their personal list.
func createMember(tx *sql.Tx, name string, admin bool, now time.Time) (string, error) {
	clean, ok := cleanName(name, maxName)
	if !ok {
		return "", errInvalid
	}
	id := newID()
	n, err := rowsChanged(tx.Exec("INSERT INTO members (id, name, name_key, is_admin, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (name_key) DO NOTHING",
		id, clean, nameKey(clean), admin, now.Unix()))
	if err != nil {
		return "", err
	}
	if n == 0 {
		return "", errConflict
	}
	if _, err := tx.Exec("INSERT INTO lists (id, owner_id) VALUES (?, ?)", newID(), id); err != nil {
		return "", err
	}
	return id, nil
}

func memberByName(tx *sql.Tx, name string) (string, error) {
	clean, ok := cleanName(name, maxName)
	if !ok {
		return "", errNotFound
	}
	var id string
	err := tx.QueryRow("SELECT id FROM members WHERE name_key = ?", nameKey(clean)).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", errNotFound
	}
	return id, err
}

// createInvite's invite is deleted with createdBy, the device that made it; nil (the CLI) means no device.
// The API is capped at maxOpenInvites open invites per member, counting every device's and the CLI's;
// the CLI (nil) isn't capped.
func createInvite(tx *sql.Tx, memberID string, createdBy *string, now time.Time) (code string, expires time.Time, err error) {
	if createdBy != nil {
		var open int
		if err := tx.QueryRow("SELECT count(*) FROM invites WHERE member_id = ? AND used_at IS NULL AND expires_at > ?",
			memberID, now.Unix()).Scan(&open); err != nil {
			return "", time.Time{}, err
		}
		if open >= maxOpenInvites {
			return "", time.Time{}, errTooManyInvites
		}
	}
	id := newID()
	secret, hash := newSecret()
	expires = now.Add(24 * time.Hour)
	// Selecting from members inserts nothing for an unknown member.
	n, err := rowsChanged(tx.Exec("INSERT INTO invites (id, member_id, secret_hash, expires_at, created_by) SELECT ?, id, ?, ?, ? FROM members WHERE id = ?",
		id, hash, expires.Unix(), createdBy, memberID))
	if err != nil {
		return "", time.Time{}, err
	}
	if n == 0 {
		return "", time.Time{}, errNotFound
	}
	return id + "." + secret, expires, nil
}

// knownMember returns errNotFound for an unknown member.
func knownMember(tx *sql.Tx, memberID string) error {
	err := tx.QueryRow("SELECT id FROM members WHERE id = ?", memberID).Scan(&memberID)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	return err
}

// revokeInvites deletes the member's unredeemed invites and returns how many it deleted.
func revokeInvites(tx *sql.Tx, memberID string) (int, error) {
	if err := knownMember(tx, memberID); err != nil {
		return 0, err
	}
	n, err := rowsChanged(tx.Exec("DELETE FROM invites WHERE member_id = ? AND used_at IS NULL", memberID))
	return int(n), err
}

// memberInvite carries no secret, hash, code or URL: the server can't show an invite again.
type memberInvite struct {
	ID        string `json:"id"`
	State     string `json:"state"`
	ExpiresAt string `json:"expires_at"`
}

// listInvites returns every invite of the member, latest expiry first, with its state as redeemInvite judges it at now.
func listInvites(tx *sql.Tx, memberID string, now time.Time) ([]memberInvite, error) {
	if err := knownMember(tx, memberID); err != nil {
		return nil, err
	}
	rows, err := tx.Query("SELECT id, expires_at, used_at IS NOT NULL FROM invites WHERE member_id = ? ORDER BY expires_at DESC, id", memberID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	invites := []memberInvite{}
	for rows.Next() {
		var i memberInvite
		var expiresAt int64
		var used bool
		if err := rows.Scan(&i.ID, &expiresAt, &used); err != nil {
			return nil, err
		}
		switch {
		case used:
			i.State = "redeemed"
		case now.Unix() >= expiresAt:
			i.State = "expired"
		default:
			i.State = "open"
		}
		i.ExpiresAt = time.Unix(expiresAt, 0).UTC().Format(time.RFC3339)
		invites = append(invites, i)
	}
	return invites, rows.Err()
}

// cancelInvite deletes one unredeemed invite, expired ones included. Another member's invite is errNotFound
// unless the caller is an admin, so that nobody learns which ids exist.
func cancelInvite(tx *sql.Tx, inviteID string, caller device) error {
	var memberID string
	var used bool
	err := tx.QueryRow("SELECT member_id, used_at IS NOT NULL FROM invites WHERE id = ?", inviteID).Scan(&memberID, &used)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	if err != nil {
		return err
	}
	if memberID != caller.MemberID && !caller.IsAdmin {
		return errNotFound
	}
	if used {
		return errInviteRedeemed
	}
	_, err = tx.Exec("DELETE FROM invites WHERE id = ?", inviteID)
	return err
}

// clearInvites deletes the member's redeemed and expired invites and returns how many it deleted. Paired devices stay.
func clearInvites(tx *sql.Tx, memberID string, now time.Time) (int, error) {
	if err := knownMember(tx, memberID); err != nil {
		return 0, err
	}
	n, err := rowsChanged(tx.Exec("DELETE FROM invites WHERE member_id = ? AND (used_at IS NOT NULL OR expires_at <= ?)", memberID, now.Unix()))
	return int(n), err
}

func redeemInvite(tx *sql.Tx, code, deviceName string, now time.Time) (token string, d device, err error) {
	inviteID, secret, ok := splitCode(code)
	if !ok {
		return "", device{}, errBadInvite
	}
	var hash []byte
	var expiresAt int64
	var usedAt *int64
	err = tx.QueryRow("SELECT i.member_id, m.is_admin, i.secret_hash, i.expires_at, i.used_at FROM invites i JOIN members m ON m.id = i.member_id WHERE i.id = ?",
		inviteID).Scan(&d.MemberID, &d.IsAdmin, &hash, &expiresAt, &usedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return "", device{}, errBadInvite
	}
	if err != nil {
		return "", device{}, err
	}
	if !secretMatches(secret, hash) || usedAt != nil || now.Unix() >= expiresAt {
		return "", device{}, errBadInvite
	}
	n, err := rowsChanged(tx.Exec("UPDATE invites SET used_at = ? WHERE id = ? AND used_at IS NULL", now.Unix(), inviteID))
	if err != nil {
		return "", device{}, err
	}
	if n != 1 {
		return "", device{}, errBadInvite
	}
	d.ID = newID()
	deviceSecret, deviceHash := newSecret()
	if _, err := tx.Exec("INSERT INTO devices (id, member_id, name, secret_hash, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)",
		d.ID, d.MemberID, cleanDeviceName(deviceName), deviceHash, now.Unix(), now.Unix()); err != nil {
		return "", device{}, err
	}
	return d.ID + "." + deviceSecret, d, nil
}

// authenticate passes database errors through, so an outage never looks like a revoked token.
func authenticate(tx *sql.Tx, token string, now time.Time) (device, error) {
	id, secret, ok := splitCode(token)
	if !ok {
		return device{}, errUnauthorized
	}
	var d device
	var hash []byte
	err := tx.QueryRow("SELECT d.id, d.member_id, m.is_admin, d.secret_hash FROM devices d JOIN members m ON m.id = d.member_id WHERE d.id = ?",
		id).Scan(&d.ID, &d.MemberID, &d.IsAdmin, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return device{}, errUnauthorized
	}
	if err != nil {
		return device{}, err
	}
	if !secretMatches(secret, hash) {
		return device{}, errUnauthorized
	}
	if _, err := tx.Exec("UPDATE devices SET last_seen_at = ? WHERE id = ?", now.Unix(), d.ID); err != nil {
		return device{}, err
	}
	return d, nil
}

func deleteDevice(tx *sql.Tx, deviceID string) error {
	n, err := rowsChanged(tx.Exec("DELETE FROM devices WHERE id = ?", deviceID))
	if err != nil {
		return err
	}
	if n == 0 {
		return errNotFound
	}
	return nil
}

// soleAdmin reports whether memberID is the only admin, and errNotFound for an unknown member.
func soleAdmin(tx *sql.Tx, memberID string) (bool, error) {
	var isAdmin bool
	var admins int
	err := tx.QueryRow("SELECT is_admin, (SELECT count(*) FROM members WHERE is_admin) FROM members WHERE id = ?",
		memberID).Scan(&isAdmin, &admins)
	if errors.Is(err, sql.ErrNoRows) {
		return false, errNotFound
	}
	return isAdmin && admins == 1, err
}

func setAdmin(tx *sql.Tx, memberID string, admin bool) error {
	sole, err := soleAdmin(tx, memberID)
	if err != nil {
		return err
	}
	if sole && !admin {
		return errLastAdmin
	}
	_, err = tx.Exec("UPDATE members SET is_admin = ? WHERE id = ?", admin, memberID)
	return err
}

// removeMember deletes the member; foreign keys cascade to their devices, invites, personal list and its entries.
func removeMember(tx *sql.Tx, memberID string) error {
	sole, err := soleAdmin(tx, memberID)
	if err != nil {
		return err
	}
	if sole {
		return errLastAdmin
	}
	_, err = tx.Exec("DELETE FROM members WHERE id = ?", memberID)
	return err
}

// inviteURL is both the QR payload and the copyable text code.
func inviteURL(publicURL, code string) string {
	return "pocketlarder://invite?server=" + url.QueryEscape(publicURL) + "&code=" + code
}
