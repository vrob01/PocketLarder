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
	key := func(name string) string {
		clean, ok := cleanName(name, maxName)
		if !ok {
			t.Fatalf("cleanName(%q) failed", name)
		}
		return nameKey(clean)
	}
	for _, p := range [][2]string{
		{"Alex", "alex"},
		{"Alex", "\u0410lex"}, // Cyrillic А
		{"Alex", "Ａｌｅｘ"},
		{"AI", "Al"}, // capital I, lowercase l
		{"Al\u00e9x", "Ale\u0301x"},
		{"Ian", "ian"},          // so i, I and l share a key
		{"Tom", "TOM"},          // m has its own prototype, rn
		{"Helen", "\u041delen"}, // Cyrillic Н
	} {
		if key(p[0]) != key(p[1]) {
			t.Errorf("nameKey(%q) = %q, nameKey(%q) = %q; want equal", p[0], key(p[0]), p[1], key(p[1]))
		}
	}
	for _, p := range [][2]string{{"Alex", "Alexa"}, {"Sam", "Pam"}, {"Jo", "Joe"}} {
		if key(p[0]) == key(p[1]) {
			t.Errorf("nameKey(%q) = nameKey(%q) = %q", p[0], p[1], key(p[0]))
		}
	}
	seen := map[string]rune{}
	for c := 'a'; c <= 'z'; c++ {
		k := nameKey(string(c))
		if prev, ok := seen[k]; ok && !(prev == 'i' && c == 'l') {
			t.Errorf("%c and %c share the key %q", prev, c, k)
		}
		seen[k] = c
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
