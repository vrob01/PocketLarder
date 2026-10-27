package larder

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

// migrations[i] upgrades the schema to version i+1. Never edit a shipped one.
var migrations = []string{
	`
CREATE TABLE members (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL UNIQUE,
  is_admin INTEGER NOT NULL DEFAULT 0,
  privacy TEXT NOT NULL DEFAULT 'open' CHECK (privacy IN ('open','readonly','hidden')),
  created_at INTEGER NOT NULL
);
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  secret_hash BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);
CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  secret_hash BLOB NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);
CREATE TABLE lists (
  id TEXT PRIMARY KEY,
  owner_id TEXT UNIQUE REFERENCES members(id) ON DELETE CASCADE, -- NULL means shared
  name TEXT,  -- shared lists only
  color TEXT, -- shared lists only
  archived INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE stores (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL);
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);
CREATE TABLE items (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL UNIQUE,
  default_store_id TEXT REFERENCES stores(id) ON DELETE SET NULL
);
CREATE TABLE placements (
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, store_id)
);
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  item_id TEXT REFERENCES items(id) ON DELETE SET NULL,
  text TEXT NOT NULL,
  quantity TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  store_id TEXT REFERENCES stores(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL,
  bought_at INTEGER
);
CREATE INDEX entries_by_list ON entries(list_id, bought_at);
CREATE TABLE applied_ops (op_id TEXT PRIMARY KEY, applied_at INTEGER NOT NULL);
`,
}

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", "file:"+path+"?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=temp_store(MEMORY)")
	if err != nil {
		return nil, err
	}
	// shortcut: one connection serialises all access, fine for a household, revisit if requests queue
	db.SetMaxOpenConns(1)
	if err := migrate(db); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func migrate(db *sql.DB) error {
	var v int
	if err := db.QueryRow("PRAGMA user_version").Scan(&v); err != nil {
		return err
	}
	if v > len(migrations) {
		return fmt.Errorf("database schema version %d is newer than this binary's %d", v, len(migrations))
	}
	for i := v; i < len(migrations); i++ {
		err := withTx(db, func(tx *sql.Tx) error {
			if _, err := tx.Exec(migrations[i]); err != nil {
				return err
			}
			_, err := tx.Exec(fmt.Sprintf("PRAGMA user_version = %d", i+1))
			return err
		})
		if err != nil {
			return fmt.Errorf("migration %d: %w", i+1, err)
		}
	}
	return nil
}

func withTx(db *sql.DB, fn func(*sql.Tx) error) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}
