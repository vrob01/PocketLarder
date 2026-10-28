package larder

import (
	"database/sql"
	"errors"
	"maps"
	"slices"
	"time"
)

// Any member may run these ops: none of them looks at admin rights.
func init() {
	maps.Copy(opHandlers, map[string]func(tx *sql.Tx, me device, o op, now time.Time) error{
		"list.create":      createList,
		"list.update":      updateList,
		"store.create":     createStore,
		"store.rename":     rename("stores"),
		"store.delete":     remove("stores"),
		"store.reorder":    reorderStores,
		"category.create":  createCategory,
		"category.rename":  rename("categories"),
		"category.delete":  remove("categories"),
		"category.reorder": reorderCategories,
		"item.update":      updateItem,
		"item.place":       placeItem,
		"item.delete":      remove("items"),
	})
}

var listColors = []string{"red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "gray"}

// opName cleans a required name.
func opName(v *string) (string, error) {
	if v == nil {
		return "", errInvalid
	}
	s, ok := cleanText(*v, maxName)
	if !ok {
		return "", errInvalid
	}
	return s, nil
}

// found is errNotFound unless table has a row with id.
func found(tx *sql.Tx, table, id string) error {
	ok, err := exists(tx, table, id)
	if err == nil && !ok {
		return errNotFound
	}
	return err
}

// freeID checks a client-made id for a new row of table, so the insert can't
// hit the primary key.
func freeID(tx *sql.Tx, table, id string) error {
	if !validID(id) {
		return errInvalid
	}
	taken, err := exists(tx, table, id)
	if err == nil && taken {
		return errConflict
	}
	return err
}

func createList(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := freeID(tx, "lists", o.ID); err != nil {
		return err
	}
	name, err := opName(o.Name)
	if err != nil {
		return err
	}
	if o.Color == nil || !slices.Contains(listColors, *o.Color) {
		return errInvalid
	}
	_, err = tx.Exec("INSERT INTO lists (id, owner_id, name, color, archived) VALUES (?, NULL, ?, ?, 0)", o.ID, name, *o.Color)
	return err
}

func updateList(tx *sql.Tx, me device, o op, now time.Time) error {
	var owner *string
	err := tx.QueryRow("SELECT owner_id FROM lists WHERE id = ?", o.ID).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	if err != nil {
		return err
	}
	if owner != nil {
		return errForbidden
	}
	if o.Name == nil && o.Color == nil && o.Archived == nil {
		return errInvalid
	}
	var name *string
	if o.Name != nil {
		s, err := opName(o.Name)
		if err != nil {
			return err
		}
		name = &s
	}
	if o.Color != nil && !slices.Contains(listColors, *o.Color) {
		return errInvalid
	}
	_, err = tx.Exec("UPDATE lists SET name = COALESCE(?, name), color = COALESCE(?, color), archived = COALESCE(?, archived) WHERE id = ?",
		name, o.Color, o.Archived, o.ID)
	return err
}

func createStore(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := freeID(tx, "stores", o.ID); err != nil {
		return err
	}
	name, err := opName(o.Name)
	if err != nil {
		return err
	}
	_, err = tx.Exec("INSERT INTO stores (id, name, position) VALUES (?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM stores))", o.ID, name)
	return err
}

func createCategory(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := freeID(tx, "categories", o.ID); err != nil {
		return err
	}
	if err := found(tx, "stores", o.StoreID); err != nil {
		return err
	}
	name, err := opName(o.Name)
	if err != nil {
		return err
	}
	_, err = tx.Exec("INSERT INTO categories (id, store_id, name, position) VALUES (?, ?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM categories WHERE store_id = ?))",
		o.ID, o.StoreID, name, o.StoreID)
	return err
}

// rename renames a store or category.
func rename(table string) func(tx *sql.Tx, me device, o op, now time.Time) error {
	return func(tx *sql.Tx, me device, o op, now time.Time) error {
		if err := found(tx, table, o.ID); err != nil {
			return err
		}
		name, err := opName(o.Name)
		if err != nil {
			return err
		}
		_, err = tx.Exec("UPDATE "+table+" SET name = ? WHERE id = ?", name, o.ID)
		return err
	}
}

// remove deletes a store, category or item. The foreign keys remove or clear
// what refers to it, and entries survive.
func remove(table string) func(tx *sql.Tx, me device, o op, now time.Time) error {
	return func(tx *sql.Tx, me device, o op, now time.Time) error {
		if err := found(tx, table, o.ID); err != nil {
			return err
		}
		_, err := tx.Exec("DELETE FROM "+table+" WHERE id = ?", o.ID)
		return err
	}
}

func reorderStores(tx *sql.Tx, me device, o op, now time.Time) error {
	return reorder(tx, "stores", o.IDs, "SELECT id FROM stores ORDER BY position, id")
}

func reorderCategories(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := found(tx, "stores", o.StoreID); err != nil {
		return err
	}
	return reorder(tx, "categories", o.IDs, "SELECT id FROM categories WHERE store_id = ? ORDER BY position, id", o.StoreID)
}

// reorder renumbers the rows of table that query selects: the listed ids
// among them first, in the order given, then the rest in their previous
// order. Unlisted rows stay, so a stale client can't knock out one it has
// never heard of.
func reorder(tx *sql.Tx, table string, ids []string, query string, args ...any) error {
	current, err := collect(tx, func(r *sql.Rows, id *string) error { return r.Scan(id) }, query, args...)
	if err != nil {
		return err
	}
	order := make([]string, 0, len(current))
	for _, id := range ids {
		if slices.Contains(current, id) && !slices.Contains(order, id) {
			order = append(order, id)
		}
	}
	for _, id := range current {
		if !slices.Contains(order, id) {
			order = append(order, id)
		}
	}
	for i, id := range order {
		if _, err := tx.Exec("UPDATE "+table+" SET position = ? WHERE id = ?", i, id); err != nil {
			return err
		}
	}
	return nil
}

func updateItem(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := found(tx, "items", o.ID); err != nil {
		return err
	}
	if o.Name == nil && o.DefaultStoreID == nil {
		return errInvalid
	}
	var name string
	if o.Name != nil {
		var err error
		if name, err = opName(o.Name); err != nil {
			return err
		}
		var taken bool
		if err := tx.QueryRow("SELECT EXISTS (SELECT 1 FROM items WHERE name_key = ? AND id != ?)", nameKey(name), o.ID).Scan(&taken); err != nil {
			return err
		}
		if taken {
			return errConflict
		}
	}
	if o.DefaultStoreID != nil && *o.DefaultStoreID != "" {
		if err := found(tx, "stores", *o.DefaultStoreID); err != nil {
			return err
		}
	}
	if o.Name != nil {
		if _, err := tx.Exec("UPDATE items SET name = ?, name_key = ? WHERE id = ?", name, nameKey(name), o.ID); err != nil {
			return err
		}
	}
	if o.DefaultStoreID != nil {
		_, err := tx.Exec("UPDATE items SET default_store_id = NULLIF(?, '') WHERE id = ?", *o.DefaultStoreID, o.ID)
		return err
	}
	return nil
}

func placeItem(tx *sql.Tx, me device, o op, now time.Time) error {
	if err := found(tx, "items", o.ID); err != nil {
		return err
	}
	if err := found(tx, "stores", o.StoreID); err != nil {
		return err
	}
	var inStore bool
	if err := tx.QueryRow("SELECT EXISTS (SELECT 1 FROM categories WHERE id = ? AND store_id = ?)", o.CategoryID, o.StoreID).Scan(&inStore); err != nil {
		return err
	}
	if !inStore {
		return errInvalid
	}
	_, err := tx.Exec("INSERT INTO placements (item_id, store_id, category_id) VALUES (?, ?, ?) ON CONFLICT (item_id, store_id) DO UPDATE SET category_id = excluded.category_id",
		o.ID, o.StoreID, o.CategoryID)
	return err
}
