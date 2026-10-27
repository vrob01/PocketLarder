package larder

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	maxName       = 100
	maxQuantity   = 32
	maxNote       = 200
	maxDeviceName = 64
)

// newID returns a random UUIDv4 in lowercase canonical form.
func newID() string {
	var b [16]byte
	// Since Go 1.24 rand.Read never returns an error; it crashes the program instead.
	rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40 // version 4
	b[8] = b[8]&0x3f | 0x80 // RFC 4122 variant
	h := hex.EncodeToString(b[:])
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

// validID checks only the shape, not the version or variant: client-made ids reach it too.
func validID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch i {
		case 8, 13, 18, 23:
			if c != '-' {
				return false
			}
		default:
			if !('0' <= c && c <= '9' || 'a' <= c && c <= 'f') {
				return false
			}
		}
	}
	return true
}

// newSecret returns a 256-bit secret and the SHA-256 hash that is stored in its place.
func newSecret() (secret string, hash []byte) {
	var b [32]byte
	rand.Read(b[:])
	secret = base64.RawURLEncoding.EncodeToString(b[:])
	sum := sha256.Sum256([]byte(secret))
	return secret, sum[:]
}

func secretMatches(secret string, hash []byte) bool {
	sum := sha256.Sum256([]byte(secret))
	return subtle.ConstantTimeCompare(sum[:], hash) == 1
}

// splitCode splits an invite code or device token, both "<uuid>.<secret>".
func splitCode(code string) (id, secret string, ok bool) {
	id, secret, found := strings.Cut(code, ".")
	if !found || !validID(id) || secret == "" {
		return "", "", false
	}
	return id, secret, true
}

// cleanText collapses whitespace first, so tabs and newlines pass but other control runes don't.
func cleanText(s string, max int) (string, bool) {
	if !utf8.ValidString(s) {
		return "", false
	}
	s = strings.Join(strings.Fields(s), " ")
	if s == "" || strings.IndexFunc(s, unicode.IsControl) >= 0 || utf8.RuneCountInString(s) > max {
		return "", false
	}
	return s, true
}

func nameKey(clean string) string {
	return strings.ToLower(clean)
}
