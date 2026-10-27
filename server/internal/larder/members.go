package larder

import (
	"database/sql"
	"errors"
	"net/url"
	"strings"
	"time"
)

type device struct {
	ID, MemberID string
	IsAdmin      bool
}

// Each message is the API error code the client sees.
var (
	errInvalid      = errors.New("invalid")
	errForbidden    = errors.New("forbidden")
	errNotFound     = errors.New("not_found")
	errConflict     = errors.New("conflict")
	errLastAdmin    = errors.New("last_admin")
	errBadInvite    = errors.New("invalid_invite")
	errUnauthorized = errors.New("unauthorized")
)

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

func createInvite(tx *sql.Tx, memberID string, now time.Time) (code string, expires time.Time, err error) {
	id := newID()
	secret, hash := newSecret()
	expires = now.Add(24 * time.Hour)
	// Selecting from members inserts nothing for an unknown member.
	n, err := rowsChanged(tx.Exec("INSERT INTO invites (id, member_id, secret_hash, expires_at) SELECT ?, id, ?, ? FROM members WHERE id = ?",
		id, hash, expires.Unix(), memberID))
	if err != nil {
		return "", time.Time{}, err
	}
	if n == 0 {
		return "", time.Time{}, errNotFound
	}
	return id + "." + secret, expires, nil
}

// revokeInvites deletes the member's unredeemed invites and returns how many it deleted.
func revokeInvites(tx *sql.Tx, memberID string) (int, error) {
	err := tx.QueryRow("SELECT id FROM members WHERE id = ?", memberID).Scan(&memberID)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, errNotFound
	}
	if err != nil {
		return 0, err
	}
	n, err := rowsChanged(tx.Exec("DELETE FROM invites WHERE member_id = ? AND used_at IS NULL", memberID))
	return int(n), err
}

// redeemInvite checks the device name first, so a bad name never uses up the invite.
func redeemInvite(tx *sql.Tx, code, deviceName string, now time.Time) (token string, d device, err error) {
	name := "Unnamed device"
	if len(strings.Fields(deviceName)) > 0 {
		var ok bool
		if name, ok = cleanName(deviceName, maxDeviceName); !ok {
			return "", device{}, errInvalid
		}
	}
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
		d.ID, d.MemberID, name, deviceHash, now.Unix(), now.Unix()); err != nil {
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
