package larder

import (
	"database/sql"
	"time"
)

const boughtPerList = 50

// visibleSQL says which lists the caller sees, over lists l LEFT JOIN members m
// ON m.id = l.owner_id, with ? the caller's member id. Admins get no exception.
const visibleSQL = "(l.owner_id IS NULL OR l.owner_id = ? OR m.privacy != 'hidden')"

type snapshot struct {
	Me         snapshotMe          `json:"me"`
	Members    []snapshotMember    `json:"members"`
	Lists      []snapshotList      `json:"lists"`
	Stores     []snapshotStore     `json:"stores"`
	Categories []snapshotCategory  `json:"categories"`
	Items      []snapshotItem      `json:"items"`
	Placements []snapshotPlacement `json:"placements"`
	Entries    []snapshotEntry     `json:"entries"`
}

type snapshotMe struct {
	MemberID string `json:"member_id"`
	DeviceID string `json:"device_id"`
	IsAdmin  bool   `json:"is_admin"`
}

type snapshotMember struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	IsAdmin bool   `json:"is_admin"`
	Privacy string `json:"privacy"`
}

type snapshotList struct {
	ID       string  `json:"id"`
	OwnerID  *string `json:"owner_id"`
	Name     *string `json:"name"`
	Color    *string `json:"color"`
	Archived bool    `json:"archived"`
	Writable bool    `json:"writable"`
}

type snapshotStore struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Position int    `json:"position"`
}

type snapshotCategory struct {
	ID       string `json:"id"`
	StoreID  string `json:"store_id"`
	Name     string `json:"name"`
	Position int    `json:"position"`
}

type snapshotItem struct {
	ID             string  `json:"id"`
	Name           string  `json:"name"`
	DefaultStoreID *string `json:"default_store_id"`
}

type snapshotPlacement struct {
	ItemID     string `json:"item_id"`
	StoreID    string `json:"store_id"`
	CategoryID string `json:"category_id"`
}

type snapshotEntry struct {
	ID        string  `json:"id"`
	ListID    string  `json:"list_id"`
	ItemID    *string `json:"item_id"`
	Text      string  `json:"text"`
	Quantity  string  `json:"quantity"`
	Note      string  `json:"note"`
	StoreID   *string `json:"store_id"`
	CreatedAt string  `json:"created_at"`
	BoughtAt  *string `json:"bought_at"`
}

// collect scans every row of query with scan. The result is never nil, so it encodes as [].
func collect[T any](tx *sql.Tx, scan func(*sql.Rows, *T) error, query string, args ...any) ([]T, error) {
	rows, err := tx.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []T{}
	for rows.Next() {
		var v T
		if err := scan(rows, &v); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// shortcut: full snapshot each sync, switch to deltas if a household's snapshot grows past ~1 MB
// shortcut: bought entries are never pruned, add pruning if the database grows noticeably
func buildSnapshot(tx *sql.Tx, me device) (snapshot, error) {
	s := snapshot{Me: snapshotMe{MemberID: me.MemberID, DeviceID: me.ID}}
	// Read here, not from me, so a member demoted mid-request isn't told they are an admin.
	if err := tx.QueryRow("SELECT is_admin FROM members WHERE id = ?", me.MemberID).Scan(&s.Me.IsAdmin); err != nil {
		return snapshot{}, err
	}
	var err error
	if s.Members, err = collect(tx, func(r *sql.Rows, v *snapshotMember) error {
		return r.Scan(&v.ID, &v.Name, &v.IsAdmin, &v.Privacy)
	}, "SELECT id, name, is_admin, privacy FROM members ORDER BY id"); err != nil {
		return snapshot{}, err
	}
	if s.Lists, err = collect(tx, func(r *sql.Rows, v *snapshotList) error {
		return r.Scan(&v.ID, &v.OwnerID, &v.Name, &v.Color, &v.Archived, &v.Writable)
	}, "SELECT l.id, l.owner_id, l.name, l.color, l.archived, "+writableSQL+" FROM lists l LEFT JOIN members m ON m.id = l.owner_id WHERE "+visibleSQL+" ORDER BY l.id",
		me.MemberID, me.MemberID); err != nil {
		return snapshot{}, err
	}
	if s.Stores, err = collect(tx, func(r *sql.Rows, v *snapshotStore) error {
		return r.Scan(&v.ID, &v.Name, &v.Position)
	}, "SELECT id, name, position FROM stores ORDER BY position, id"); err != nil {
		return snapshot{}, err
	}
	if s.Categories, err = collect(tx, func(r *sql.Rows, v *snapshotCategory) error {
		return r.Scan(&v.ID, &v.StoreID, &v.Name, &v.Position)
	}, "SELECT id, store_id, name, position FROM categories ORDER BY position, id"); err != nil {
		return snapshot{}, err
	}
	if s.Items, err = collect(tx, func(r *sql.Rows, v *snapshotItem) error {
		return r.Scan(&v.ID, &v.Name, &v.DefaultStoreID)
	}, "SELECT id, name, default_store_id FROM items ORDER BY id"); err != nil {
		return snapshot{}, err
	}
	if s.Placements, err = collect(tx, func(r *sql.Rows, v *snapshotPlacement) error {
		return r.Scan(&v.ItemID, &v.StoreID, &v.CategoryID)
	}, "SELECT item_id, store_id, category_id FROM placements ORDER BY item_id, store_id"); err != nil {
		return snapshot{}, err
	}
	// n numbers the bought entries of each list newest first: DESC puts the open ones (NULL) last.
	s.Entries, err = collect(tx, func(r *sql.Rows, v *snapshotEntry) error {
		var created int64
		var bought *int64
		if err := r.Scan(&v.ID, &v.ListID, &v.ItemID, &v.Text, &v.Quantity, &v.Note, &v.StoreID, &created, &bought); err != nil {
			return err
		}
		v.CreatedAt = time.Unix(created, 0).UTC().Format(time.RFC3339)
		if bought != nil {
			b := time.Unix(*bought, 0).UTC().Format(time.RFC3339)
			v.BoughtAt = &b
		}
		return nil
	}, `SELECT id, list_id, item_id, text, quantity, note, store_id, created_at, bought_at FROM (
  SELECT e.*, ROW_NUMBER() OVER (PARTITION BY e.list_id ORDER BY e.bought_at DESC, e.id) AS n
  FROM entries e JOIN lists l ON l.id = e.list_id LEFT JOIN members m ON m.id = l.owner_id
  WHERE `+visibleSQL+`
) WHERE bought_at IS NULL OR n <= ?
ORDER BY id`, me.MemberID, boughtPerList)
	if err != nil {
		return snapshot{}, err
	}
	return s, nil
}
