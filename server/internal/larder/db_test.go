package larder

import (
	"path/filepath"
	"testing"
)

func TestOpenDBMigratesOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "p.db")
	db, err := openDB(path) // first open creates the schema
	if err != nil {
		t.Fatal(err)
	}
	db.Close()
	db, err = openDB(path) // second open must not re-run migration 1
	if err != nil {
		t.Fatal(err)
	}
	var v int
	db.QueryRow("PRAGMA user_version").Scan(&v)
	if v != len(migrations) {
		t.Fatalf("user_version = %d, want %d", v, len(migrations))
	}
}

func TestDeletingStoreNullsReferencesAndKeepsEntries(t *testing.T) {
	db := testDB(t)
	for _, q := range []string{
		"INSERT INTO stores (id, name, position) VALUES ('s', 'Corner shop', 0)",
		"INSERT INTO categories (id, store_id, name, position) VALUES ('c', 's', 'Dairy', 0)",
		"INSERT INTO items (id, name, name_key, default_store_id) VALUES ('i', 'Milk', 'milk', 's')",
		"INSERT INTO placements (item_id, store_id, category_id) VALUES ('i', 's', 'c')",
		"INSERT INTO members (id, name, name_key, created_at) VALUES ('m', 'Alex', 'alex', 0)",
		"INSERT INTO lists (id, owner_id) VALUES ('l', 'm')",
		"INSERT INTO entries (id, list_id, item_id, text, store_id, created_at) VALUES ('e', 'l', 'i', 'Milk', 's', 0)",
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}

	if _, err := db.Exec("DELETE FROM stores WHERE id = ?", "s"); err != nil {
		t.Fatal(err)
	}

	for _, table := range []string{"categories", "placements"} {
		var n int
		if err := db.QueryRow("SELECT count(*) FROM "+table+" WHERE store_id = ?", "s").Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Errorf("%d %s rows of the deleted store remain, want 0", n, table)
		}
	}
	var defaultStore *string
	if err := db.QueryRow("SELECT default_store_id FROM items WHERE id = ?", "i").Scan(&defaultStore); err != nil {
		t.Fatal(err)
	}
	if defaultStore != nil {
		t.Errorf("items.default_store_id = %q, want NULL", *defaultStore)
	}
	var entryStore *string
	if err := db.QueryRow("SELECT store_id FROM entries WHERE id = ?", "e").Scan(&entryStore); err != nil {
		t.Fatalf("entry e after deleting its store: %v", err)
	}
	if entryStore != nil {
		t.Errorf("entries.store_id = %q, want NULL", *entryStore)
	}
}
