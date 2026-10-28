package larder

import (
	"database/sql"
	"errors"
	"time"
)

const maxOps = 500

// op is one queued change from a client. Absent pointer fields mean "unchanged".
type op struct {
	OpID           string   `json:"op_id"`
	Type           string   `json:"type"`
	ID             string   `json:"id"`
	ListID         string   `json:"list_id"`
	ItemID         string   `json:"item_id"`
	StoreID        string   `json:"store_id"`
	CategoryID     string   `json:"category_id"`
	NewItemID      string   `json:"new_item_id"`
	Text           *string  `json:"text"`
	Quantity       *string  `json:"quantity"`
	Note           *string  `json:"note"`
	Name           *string  `json:"name"`
	Color          *string  `json:"color"`
	DefaultStoreID *string  `json:"default_store_id"`
	Archived       *bool    `json:"archived"`
	IDs            []string `json:"ids"`
	Privacy        string   `json:"privacy"`
}

type rejection struct {
	OpID   string `json:"op_id"`
	Reason string `json:"reason"`
}

// Each handler checks everything it can reject before its first write, so a
// rejected op changes nothing.
var opHandlers = map[string]func(tx *sql.Tx, me device, o op, now time.Time) error{
	"entry.add":          addEntry,
	"entry.update":       updateEntry,
	"entry.buy":          buyEntry,
	"entry.unbuy":        unbuyEntry,
	"entry.delete":       deleteEntry,
	"entry.place":        placeEntry,
	"member.set_privacy": setPrivacy,
}

// applyBatch returns sentinel errors as rejections and any other error as is,
// so the caller rolls back the whole batch, its applied_ops rows included.
func applyBatch(tx *sql.Tx, me device, ops []op, now time.Time) ([]rejection, error) {
	if _, err := tx.Exec("DELETE FROM applied_ops WHERE applied_at < ?", now.Add(-90*24*time.Hour).Unix()); err != nil {
		return nil, err
	}
	rejected := []rejection{}
	for _, o := range ops {
		if !validID(o.OpID) {
			rejected = append(rejected, rejection{o.OpID, errInvalid.Error()})
			continue
		}
		n, err := rowsChanged(tx.Exec("INSERT OR IGNORE INTO applied_ops (op_id, applied_at) VALUES (?, ?)", o.OpID, now.Unix()))
		if err != nil {
			return nil, err
		}
		if n == 0 {
			continue // an earlier delivery of this op was applied
		}
		h, ok := opHandlers[o.Type]
		if !ok {
			rejected = append(rejected, rejection{o.OpID, errInvalid.Error()})
			continue
		}
		err = h(tx, me, o, now)
		if _, sentinel := errStatus[err]; sentinel {
			rejected = append(rejected, rejection{o.OpID, err.Error()})
		} else if err != nil {
			return nil, err
		}
	}
	return rejected, nil
}

// writableSQL is writableList's rule over lists l LEFT JOIN members m ON m.id = l.owner_id,
// with ? the caller's member id. It never looks at admin rights.
const writableSQL = "(l.owner_id IS NULL OR l.owner_id = ? OR m.privacy = 'open')"

func writableList(tx *sql.Tx, me device, listID string) error {
	var ok bool
	err := tx.QueryRow("SELECT "+writableSQL+" FROM lists l LEFT JOIN members m ON m.id = l.owner_id WHERE l.id = ?",
		me.MemberID, listID).Scan(&ok)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	if err != nil {
		return err
	}
	if !ok {
		return errForbidden
	}
	return nil
}

// writableEntry looks up an entry and checks that me may change its list.
func writableEntry(tx *sql.Tx, me device, id string) (itemID *string, text string, err error) {
	var listID string
	err = tx.QueryRow("SELECT list_id, item_id, text FROM entries WHERE id = ?", id).Scan(&listID, &itemID, &text)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, "", errNotFound
	}
	if err != nil {
		return nil, "", err
	}
	return itemID, text, writableList(tx, me, listID)
}

func exists(tx *sql.Tx, table, id string) (bool, error) {
	var ok bool
	err := tx.QueryRow("SELECT EXISTS (SELECT 1 FROM "+table+" WHERE id = ?)", id).Scan(&ok)
	return ok, err
}

// cleanOptional cleans a quantity or note. Absent stays nil and "" stays "", which clears the field.
func cleanOptional(v *string, max int) (*string, error) {
	if v == nil || *v == "" {
		return v, nil
	}
	s, ok := cleanText(*v, max)
	if !ok {
		return nil, errInvalid
	}
	return &s, nil
}

func addEntry(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := writableList(tx, me, o.ListID); err != nil {
		return err
	}
	if !validID(o.ID) {
		return errInvalid
	}
	if taken, err := exists(tx, "entries", o.ID); err != nil || taken {
		return err // an existing entry makes the add a no-op
	}
	quantity, err := cleanOptional(o.Quantity, maxQuantity)
	if err != nil {
		return err
	}
	note, err := cleanOptional(o.Note, maxNote)
	if err != nil {
		return err
	}
	var itemID, storeID *string
	var text string
	if o.ItemID != "" {
		err := tx.QueryRow("SELECT name, default_store_id FROM items WHERE id = ?", o.ItemID).Scan(&text, &storeID)
		if errors.Is(err, sql.ErrNoRows) {
			return errNotFound
		}
		if err != nil {
			return err
		}
		itemID = &o.ItemID
		if o.StoreID != "" {
			ok, err := exists(tx, "stores", o.StoreID)
			if err != nil {
				return err
			}
			if !ok {
				return errNotFound
			}
			storeID = &o.StoreID
		}
	} else {
		var ok bool
		if o.Text != nil {
			text, ok = cleanText(*o.Text, maxName)
		}
		if !ok || o.StoreID != "" {
			return errInvalid
		}
	}
	_, err = tx.Exec("INSERT INTO entries (id, list_id, item_id, text, quantity, note, store_id, created_at) VALUES (?, ?, ?, ?, COALESCE(?, ''), COALESCE(?, ''), ?, ?)",
		o.ID, o.ListID, itemID, text, quantity, note, storeID, now.Unix())
	return err
}

func updateEntry(tx *sql.Tx, me device, o op, now time.Time) error {
	if _, _, err := writableEntry(tx, me, o.ID); err != nil {
		return err
	}
	if o.Quantity == nil && o.Note == nil {
		return errInvalid
	}
	quantity, err := cleanOptional(o.Quantity, maxQuantity)
	if err != nil {
		return err
	}
	note, err := cleanOptional(o.Note, maxNote)
	if err != nil {
		return err
	}
	_, err = tx.Exec("UPDATE entries SET quantity = COALESCE(?, quantity), note = COALESCE(?, note) WHERE id = ?", quantity, note, o.ID)
	return err
}

func buyEntry(tx *sql.Tx, me device, o op, now time.Time) error {
	if _, _, err := writableEntry(tx, me, o.ID); err != nil {
		return err
	}
	_, err := tx.Exec("UPDATE entries SET bought_at = COALESCE(bought_at, ?) WHERE id = ?", now.Unix(), o.ID)
	return err
}

func unbuyEntry(tx *sql.Tx, me device, o op, now time.Time) error {
	if _, _, err := writableEntry(tx, me, o.ID); err != nil {
		return err
	}
	_, err := tx.Exec("UPDATE entries SET bought_at = NULL WHERE id = ?", o.ID)
	return err
}

func deleteEntry(tx *sql.Tx, me device, o op, now time.Time) error {
	if _, _, err := writableEntry(tx, me, o.ID); err != nil {
		return err
	}
	_, err := tx.Exec("DELETE FROM entries WHERE id = ?", o.ID)
	return err
}

// placeEntry files an entry in a store, linking an unfiled entry to the item
// of the same name or creating that item.
func placeEntry(tx *sql.Tx, me device, o op, now time.Time) error {
	itemID, text, err := writableEntry(tx, me, o.ID)
	if err != nil {
		return err
	}
	ok, err := exists(tx, "stores", o.StoreID)
	if err != nil {
		return err
	}
	if !ok {
		return errNotFound
	}
	if o.CategoryID != "" {
		var inStore bool
		if err := tx.QueryRow("SELECT EXISTS (SELECT 1 FROM categories WHERE id = ? AND store_id = ?)", o.CategoryID, o.StoreID).Scan(&inStore); err != nil {
			return err
		}
		if !inStore {
			return errInvalid
		}
	}
	if itemID == nil {
		if o.CategoryID == "" || !validID(o.NewItemID) {
			return errInvalid
		}
		key := nameKey(text)
		err := tx.QueryRow("SELECT id FROM items WHERE name_key = ?", key).Scan(&itemID)
		if errors.Is(err, sql.ErrNoRows) {
			taken, err := exists(tx, "items", o.NewItemID)
			if err != nil {
				return err
			}
			if taken {
				return errConflict
			}
			if _, err := tx.Exec("INSERT INTO items (id, name, name_key, default_store_id) VALUES (?, ?, ?, ?)", o.NewItemID, text, key, o.StoreID); err != nil {
				return err
			}
			itemID = &o.NewItemID
		} else if err != nil {
			return err
		}
	}
	if _, err := tx.Exec("UPDATE entries SET item_id = ?, store_id = ? WHERE id = ?", *itemID, o.StoreID, o.ID); err != nil {
		return err
	}
	if o.CategoryID != "" {
		if _, err := tx.Exec("INSERT INTO placements (item_id, store_id, category_id) VALUES (?, ?, ?) ON CONFLICT (item_id, store_id) DO UPDATE SET category_id = excluded.category_id",
			*itemID, o.StoreID, o.CategoryID); err != nil {
			return err
		}
	}
	_, err = tx.Exec("UPDATE items SET default_store_id = ? WHERE id = ? AND default_store_id IS NULL", o.StoreID, *itemID)
	return err
}

func setPrivacy(tx *sql.Tx, me device, o op, now time.Time) error {
	switch o.Privacy {
	case "open", "readonly", "hidden":
	default:
		return errInvalid
	}
	_, err := tx.Exec("UPDATE members SET privacy = ? WHERE id = ?", o.Privacy, me.MemberID)
	return err
}
