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
		{"A\u0308pfel", maxName, "Äpfel", true},               // decomposed Ä becomes NFC
		{"👩\u200d👩\u200d👧", maxName, "👩\u200d👩\u200d👧", true}, // emoji sequences need U+200D
		{"می\u200cخواهم", maxName, "می\u200cخواهم", true},     // Persian needs U+200C
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

func TestCleanName(t *testing.T) {
	for _, c := range []struct {
		in   string
		want string
		ok   bool
	}{
		{"  Alex \t Smith ", "Alex Smith", true},
		{"Ａｌｅｘ", "Alex", true},
		{"Ale\u0301x", "Al\u00e9x", true},
		{"Alex\u200b", "", false}, // zero-width space
		{"\u202eAlex", "", false}, // bidi override
		{"Al\u200dex", "", false}, // stray joiner
		{"a\x00b", "", false},
		{"\xff", "", false},
		{"   ", "", false},
		{strings.Repeat("x", 100), strings.Repeat("x", 100), true},
		{strings.Repeat("x", 101), "", false},
		{strings.Repeat("ﬁ", 51), "", false}, // the limit applies after NFKC turns each ﬁ into fi
	} {
		got, ok := cleanName(c.in, maxName)
		if got != c.want || ok != c.ok {
			t.Errorf("cleanName(%q) = %q, %v; want %q, %v", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestNameKey(t *testing.T) {
	key := func(clean func(string, int) (string, bool), name string) string {
		s, ok := clean(name, maxName)
		if !ok {
			t.Fatalf("cleaning %q failed", name)
		}
		return nameKey(s)
	}
	for _, c := range []struct {
		clean   func(string, int) (string, bool)
		a, b    string
		collide bool
	}{
		{cleanName, "Alex", "alex", true},
		{cleanName, "Alex", "ALEX", true},
		{cleanName, "Al\u00e9x", "Ale\u0301x", true},
		{cleanName, "Ａｌｅｘ", "Alex", true}, // member names get NFKC
		{cleanText, "Milk", "milk", true},
		{cleanText, "Al\u00e9x", "Ale\u0301x", true},
		{cleanName, "Ilse", "Lise", false},
		{cleanName, "Ella", "Eila", false},
		{cleanName, "Kim", "Kirn", false},
		{cleanName, "Lia", "Ila", false},
		{cleanName, "Alex", "\u0410lex", false}, // Cyrillic А, an accepted residual
	} {
		if ka, kb := key(c.clean, c.a), key(c.clean, c.b); (ka == kb) != c.collide {
			t.Errorf("nameKey(%q) = %q, nameKey(%q) = %q; want collide = %v", c.a, ka, c.b, kb, c.collide)
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
