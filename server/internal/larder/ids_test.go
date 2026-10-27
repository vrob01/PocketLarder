package larder

import (
	"strings"
	"testing"
)

func TestCleanText(t *testing.T) {
	for _, c := range []struct {
		in   string
		max  int
		want string
		ok   bool
	}{
		{"  Burrito \t spice ", maxName, "Burrito spice", true},
		{"Äpfel", maxName, "Äpfel", true},
		{"line\nbreak", maxName, "line break", true},
		{"", maxName, "", false},
		{"   ", maxName, "", false},
		{"a\x00b", maxName, "", false},
		{"a\u0085b", maxName, "a b", true}, // NEL is whitespace, so it collapses before the control check
		{"a\u007fb", maxName, "", false},
		{"\xff", maxName, "", false},
		{strings.Repeat("x", 100), 100, strings.Repeat("x", 100), true},
		{strings.Repeat("x", 101), 100, "", false},
		{strings.Repeat("ä", 64), maxDeviceName, strings.Repeat("ä", 64), true},
	} {
		got, ok := cleanText(c.in, c.max)
		if got != c.want || ok != c.ok {
			t.Errorf("cleanText(%q, %d) = %q, %v; want %q, %v", c.in, c.max, got, ok, c.want, c.ok)
		}
	}
}

func TestIDs(t *testing.T) {
	id := newID()
	if !validID(id) {
		t.Errorf("validID(%q) = false", id)
	}
	if id[14] != '4' || !strings.ContainsRune("89ab", rune(id[19])) {
		t.Errorf("newID() = %q, want version 4 and the RFC 4122 variant", id)
	}
	if validID("x") {
		t.Error(`validID("x") = true`)
	}
	if upper := strings.ToUpper(newID()); validID(upper) {
		t.Errorf("validID(%q) = true", upper)
	}
	if a, b := newID(), newID(); a == b {
		t.Errorf("two newID() calls both returned %q", a)
	}

	secret, hash := newSecret()
	if len(secret) != 43 || len(hash) != 32 {
		t.Errorf("newSecret() = %d chars, %d-byte hash; want 43, 32", len(secret), len(hash))
	}
	if !secretMatches(secret, hash) || secretMatches(secret+"x", hash) {
		t.Error("secretMatches does not tell the secret from another")
	}
	for _, code := range []string{"", "garbage", id, id + ".", "x." + secret, strings.ToUpper(id) + "." + secret} {
		if _, _, ok := splitCode(code); ok {
			t.Errorf("splitCode(%q) ok", code)
		}
	}
	if gotID, gotSecret, ok := splitCode(id + "." + secret); !ok || gotID != id || gotSecret != secret {
		t.Errorf("splitCode did not split a valid code: %q, %q, %v", gotID, gotSecret, ok)
	}
}
