package larder

import (
	"database/sql"
	"path/filepath"
	"testing"
)

// testDB opens a fresh, migrated database that is closed when the test ends.
func testDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := openDB(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func ptr[T any](v T) *T { return &v }
