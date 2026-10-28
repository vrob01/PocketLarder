package larder

import (
	"slices"
	"testing"
)

func nameOp(typ, id, name string) op {
	return op{OpID: newID(), Type: typ, ID: id, Name: ptr(name)}
}

func categoryOp(id, storeID, name string) op {
	return op{OpID: newID(), Type: "category.create", ID: id, StoreID: storeID, Name: ptr(name)}
}

func reorderOp(typ, storeID string, ids ...string) op {
	return op{OpID: newID(), Type: typ, StoreID: storeID, IDs: ids}
}

func itemPlaceOp(itemID, storeID, categoryID string) op {
	return op{OpID: newID(), Type: "item.place", ID: itemID, StoreID: storeID, CategoryID: categoryID}
}

func itemIn(s snapshot, id string) *snapshotItem {
	if i := slices.IndexFunc(s.Items, func(x snapshotItem) bool { return x.ID == id }); i >= 0 {
		return &s.Items[i]
	}
	return nil
}

// filed adds an entry with text to the list and files it in the store and
// category, which creates its item. It returns the entry and item ids.
func (e *testEnv) filed(token, listID, text, storeID, categoryID string) (entryID, itemID string) {
	e.t.Helper()
	add := addOp(listID, text)
	place := placeOp(add.ID, storeID, categoryID)
	rejected, _ := e.sync(token, add, place)
	wantRejected(e.t, rejected)
	return add.ID, place.NewItemID
}

func TestStoresAndCategories(t *testing.T) {
	e := newTestEnv(t)
	_, token := e.member("Alex", true)
	a, b := nameOp("store.create", newID(), " A "), nameOp("store.create", newID(), "B")
	taken := nameOp("store.create", a.ID, "C")
	badID := nameOp("store.create", "not-a-uuid", "C")
	noName := entryOp("store.create", newID())
	rejected, s := e.sync(token, a, b, taken, badID, noName)
	wantRejected(t, rejected, rejection{taken.OpID, "conflict"}, rejection{badID.OpID, "invalid"}, rejection{noName.OpID, "invalid"})
	if want := []snapshotStore{{a.ID, "A", 0}, {b.ID, "B", 1}}; !slices.Equal(s.Stores, want) {
		t.Errorf("stores = %+v, want %+v", s.Stores, want)
	}

	rejected, s = e.sync(token, reorderOp("store.reorder", "", b.ID, a.ID))
	wantRejected(t, rejected)
	if want := []snapshotStore{{b.ID, "B", 0}, {a.ID, "A", 1}}; !slices.Equal(s.Stores, want) {
		t.Errorf("reordered stores = %+v, want %+v", s.Stores, want)
	}

	x, y := categoryOp(newID(), a.ID, "x"), categoryOp(newID(), a.ID, "y")
	takenCategory := categoryOp(x.ID, a.ID, "z")
	noStore := categoryOp(newID(), newID(), "z")
	renameY := nameOp("category.rename", y.ID, " Fruit  and veg ")
	renameStore := nameOp("store.rename", b.ID, "Bakery")
	unknown := []op{
		nameOp("store.rename", newID(), "Bakery"),
		nameOp("category.rename", newID(), "Bakery"),
		entryOp("store.delete", newID()),
		entryOp("category.delete", newID()),
		entryOp("item.delete", newID()),
		reorderOp("category.reorder", newID(), x.ID),
	}
	badName := nameOp("category.rename", x.ID, " \t ")
	rejected, s = e.sync(token, append([]op{x, y, takenCategory, noStore, renameY, renameStore, badName}, unknown...)...)
	want := []rejection{{takenCategory.OpID, "conflict"}, {noStore.OpID, "not_found"}, {badName.OpID, "invalid"}}
	for _, o := range unknown {
		want = append(want, rejection{o.OpID, "not_found"})
	}
	wantRejected(t, rejected, want...)
	if want := []snapshotCategory{{x.ID, a.ID, "x", 0}, {y.ID, a.ID, "Fruit and veg", 1}}; !slices.Equal(s.Categories, want) {
		t.Errorf("categories = %+v, want %+v", s.Categories, want)
	}
	if want := []snapshotStore{{b.ID, "Bakery", 0}, {a.ID, "A", 1}}; !slices.Equal(s.Stores, want) {
		t.Errorf("stores after rename = %+v, want %+v", s.Stores, want)
	}

	rejected, s = e.sync(token, reorderOp("category.reorder", a.ID, y.ID, x.ID))
	wantRejected(t, rejected)
	if want := []snapshotCategory{{y.ID, a.ID, "Fruit and veg", 0}, {x.ID, a.ID, "x", 1}}; !slices.Equal(s.Categories, want) {
		t.Errorf("reordered categories = %+v, want %+v", s.Categories, want)
	}
}

func TestReorderKeepsUnlisted(t *testing.T) {
	e := newTestEnv(t)
	_, token := e.member("Alex", true)
	a, b, c := e.store("A"), e.store("B"), e.store("C")

	// Unknown ids are ignored and a repeated id counts where it first appears.
	rejected, s := e.sync(token, reorderOp("store.reorder", "", c, newID(), a, c))
	wantRejected(t, rejected)
	if want := []snapshotStore{{c, "C", 0}, {a, "A", 1}, {b, "B", 2}}; !slices.Equal(s.Stores, want) {
		t.Errorf("stores = %+v, want %+v", s.Stores, want)
	}

	a1, a2 := e.category(a, "a1"), e.category(a, "a2")
	b1, b2 := e.category(b, "b1"), e.category(b, "b2")
	// b2 is in another store, so it is an unknown id here and B keeps its order.
	rejected, s = e.sync(token, reorderOp("category.reorder", a, b2, a2))
	wantRejected(t, rejected)
	inStore := func(storeID string) []snapshotCategory {
		return slices.DeleteFunc(slices.Clone(s.Categories), func(c snapshotCategory) bool { return c.StoreID != storeID })
	}
	if want := []snapshotCategory{{a2, a, "a2", 0}, {a1, a, "a1", 1}}; !slices.Equal(inStore(a), want) {
		t.Errorf("categories of A = %+v, want %+v", inStore(a), want)
	}
	if want := []snapshotCategory{{b1, b, "b1", 0}, {b2, b, "b2", 1}}; !slices.Equal(inStore(b), want) {
		t.Errorf("categories of B = %+v, want %+v", inStore(b), want)
	}

	// An empty reorder closes the gap a delete leaves.
	rejected, s = e.sync(token, entryOp("store.delete", c), reorderOp("store.reorder", ""))
	wantRejected(t, rejected)
	if want := []snapshotStore{{a, "A", 0}, {b, "B", 1}}; !slices.Equal(s.Stores, want) {
		t.Errorf("stores after delete = %+v, want %+v", s.Stores, want)
	}
}

func TestDeletingStoreKeepsEntries(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	store := e.store("Grocer")
	entry, item := e.filed(token, e.personalList(alex), "Milk", store, e.category(store, "Dairy"))

	rejected, s := e.sync(token, entryOp("store.delete", store))
	wantRejected(t, rejected)
	if got := entryIn(s, entry); got == nil || got.StoreID != nil || got.ItemID == nil || *got.ItemID != item || got.Text != "Milk" {
		t.Errorf("entry = %+v, want Milk with item %s and no store", got, item)
	}
	if got := itemIn(s, item); got == nil || got.DefaultStoreID != nil {
		t.Errorf("item = %+v, want no default store", got)
	}
	if len(s.Stores) != 0 || len(s.Categories) != 0 || len(s.Placements) != 0 {
		t.Errorf("stores %+v, categories %+v, placements %+v; want none", s.Stores, s.Categories, s.Placements)
	}
}

func TestDeletingCategoryKeepsEntries(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	store, bakery := e.store("Grocer"), e.store("Bakery")
	dairy, fridge := e.category(store, "Dairy"), e.category(store, "Fridge")
	bread := e.category(bakery, "Bread")
	entry, item := e.filed(token, e.personalList(alex), "Milk", store, dairy)

	foreign := itemPlaceOp(item, store, bread)
	noCategory := itemPlaceOp(item, store, "")
	noItem := itemPlaceOp(newID(), store, fridge)
	noStore := itemPlaceOp(item, newID(), fridge)
	move := itemPlaceOp(item, store, fridge)
	rejected, s := e.sync(token, foreign, noCategory, noItem, noStore, move)
	wantRejected(t, rejected, rejection{foreign.OpID, "invalid"}, rejection{noCategory.OpID, "invalid"},
		rejection{noItem.OpID, "not_found"}, rejection{noStore.OpID, "not_found"})
	if want := []snapshotPlacement{{item, store, fridge}}; !slices.Equal(s.Placements, want) {
		t.Errorf("placements = %+v, want %+v", s.Placements, want)
	}

	rejected, s = e.sync(token, entryOp("category.delete", fridge))
	wantRejected(t, rejected)
	if got := entryIn(s, entry); got == nil || got.StoreID == nil || *got.StoreID != store || got.ItemID == nil || *got.ItemID != item {
		t.Errorf("entry = %+v, want item %s in store %s", got, item, store)
	}
	if len(s.Placements) != 0 {
		t.Errorf("placements = %+v, want none", s.Placements)
	}
	if len(s.Categories) != 2 || slices.ContainsFunc(s.Categories, func(c snapshotCategory) bool { return c.ID == fridge }) {
		t.Errorf("categories = %+v, want Dairy and Bread", s.Categories)
	}
}

func TestDeletingItemKeepsEntryText(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	store := e.store("Grocer")
	entry, item := e.filed(token, e.personalList(alex), "  Oat \t milk ", store, e.category(store, "Dairy"))

	rejected, s := e.sync(token, entryOp("item.delete", item))
	wantRejected(t, rejected)
	if got := entryIn(s, entry); got == nil || got.ItemID != nil || got.Text != "Oat milk" || got.StoreID == nil || *got.StoreID != store {
		t.Errorf("entry = %+v, want text Oat milk in store %s with no item", got, store)
	}
	if len(s.Items) != 0 || len(s.Placements) != 0 {
		t.Errorf("items %+v, placements %+v; want none", s.Items, s.Placements)
	}
}

func TestItemRenameConflict(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	list := e.personalList(alex)
	store, bakery := e.store("Grocer"), e.store("Bakery")
	category := e.category(store, "Aisle 1")
	milkEntry, milk := e.filed(token, list, "Milk", store, category)
	_, bread := e.filed(token, list, "Bread", store, category)

	conflict := nameOp("item.update", milk, "BREAD")
	missing := nameOp("item.update", newID(), "Cheese")
	empty := entryOp("item.update", milk)
	badName := nameOp("item.update", milk, "")
	noStore := entryOp("item.update", milk)
	noStore.DefaultStoreID = ptr(newID())
	rejected, s := e.sync(token, conflict, missing, empty, badName, noStore)
	wantRejected(t, rejected, rejection{conflict.OpID, "conflict"}, rejection{missing.OpID, "not_found"},
		rejection{empty.OpID, "invalid"}, rejection{badName.OpID, "invalid"}, rejection{noStore.OpID, "not_found"})
	if m, b := itemIn(s, milk), itemIn(s, bread); m == nil || m.Name != "Milk" || b == nil || b.Name != "Bread" {
		t.Errorf("items = %+v, want Milk and Bread unchanged", s.Items)
	}

	caseOnly := nameOp("item.update", milk, "MILK")
	caseOnly.DefaultStoreID = &bakery
	rejected, s = e.sync(token, caseOnly)
	wantRejected(t, rejected)
	if got := itemIn(s, milk); got == nil || got.Name != "MILK" || got.DefaultStoreID == nil || *got.DefaultStoreID != bakery {
		t.Errorf("item = %+v, want MILK with default store %s", got, bakery)
	}
	if got := entryIn(s, milkEntry); got == nil || got.Text != "Milk" {
		t.Errorf("entry = %+v, want its text still Milk", got)
	}

	clear := entryOp("item.update", milk)
	clear.DefaultStoreID = ptr("")
	rejected, s = e.sync(token, clear)
	wantRejected(t, rejected)
	if got := itemIn(s, milk); got == nil || got.Name != "MILK" || got.DefaultStoreID != nil {
		t.Errorf("item = %+v, want MILK with no default store", got)
	}
}

func TestSharedLists(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	_, user := e.member("Sam", false)
	party := nameOp("list.create", newID(), "Party")
	party.Color = ptr("teal")
	chartreuse := nameOp("list.create", newID(), "Picnic")
	chartreuse.Color = ptr("chartreuse")
	noColor := nameOp("list.create", newID(), "Picnic")
	taken := nameOp("list.create", party.ID, "Picnic")
	taken.Color = ptr("green")
	rejected, _ := e.sync(admin, party, chartreuse, noColor, taken)
	wantRejected(t, rejected, rejection{chartreuse.OpID, "invalid"}, rejection{noColor.OpID, "invalid"}, rejection{taken.OpID, "conflict"})

	_, s := e.sync(user)
	l := listIn(s, party.ID)
	if l == nil || l.OwnerID != nil || l.Name == nil || *l.Name != "Party" || l.Color == nil || *l.Color != "teal" || l.Archived || !l.Writable {
		t.Errorf("Party for Sam = %+v, want shared, teal, not archived and writable", l)
	}
	if listIn(s, chartreuse.ID) != nil || listIn(s, noColor.ID) != nil {
		t.Error("a rejected list.create made a list")
	}

	archive := entryOp("list.update", party.ID)
	archive.Archived = ptr(true)
	personal := nameOp("list.update", e.personalList(alex), "Mine")
	empty := entryOp("list.update", party.ID)
	badColor := entryOp("list.update", party.ID)
	badColor.Color = ptr("chartreuse")
	missing := entryOp("list.update", newID())
	missing.Archived = ptr(true)
	rejected, s = e.sync(admin, archive, personal, empty, badColor, missing)
	wantRejected(t, rejected, rejection{personal.OpID, "forbidden"}, rejection{empty.OpID, "invalid"},
		rejection{badColor.OpID, "invalid"}, rejection{missing.OpID, "not_found"})
	if l := listIn(s, party.ID); l == nil || !l.Archived || l.Name == nil || *l.Name != "Party" || l.Color == nil || *l.Color != "teal" {
		t.Errorf("archived Party = %+v, want it in the snapshot, archived, still Party and teal", l)
	}
	if l := listIn(s, e.personalList(alex)); l == nil || l.Name != nil {
		t.Errorf("Alex's list = %+v, want no name", l)
	}

	update := nameOp("list.update", party.ID, " Picnic ")
	update.Color, update.Archived = ptr("green"), ptr(false)
	rejected, s = e.sync(user, update)
	wantRejected(t, rejected)
	if l := listIn(s, party.ID); l == nil || l.Archived || l.Name == nil || *l.Name != "Picnic" || l.Color == nil || *l.Color != "green" {
		t.Errorf("updated list = %+v, want Picnic, green, not archived", l)
	}
}
