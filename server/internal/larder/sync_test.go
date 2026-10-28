package larder

import (
	"net/http"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"
)

// sync posts ops to /v1/sync, wants 200 and returns the rejections and the snapshot.
func (e *testEnv) sync(token string, ops ...op) ([]rejection, snapshot) {
	e.t.Helper()
	var resp struct {
		Rejected []rejection `json:"rejected"`
		Snapshot snapshot    `json:"snapshot"`
	}
	e.decode(e.call("POST", "/v1/sync", token, map[string][]op{"ops": ops}), http.StatusOK, &resp)
	return resp.Rejected, resp.Snapshot
}

// store inserts a store with SQL and returns its id.
func (e *testEnv) store(name string) string {
	e.t.Helper()
	id := newID()
	if _, err := e.db.Exec("INSERT INTO stores (id, name, position) VALUES (?, ?, (SELECT count(*) FROM stores))", id, name); err != nil {
		e.t.Fatal(err)
	}
	return id
}

// category inserts a category of the store with SQL and returns its id.
func (e *testEnv) category(storeID, name string) string {
	e.t.Helper()
	id := newID()
	if _, err := e.db.Exec("INSERT INTO categories (id, store_id, name, position) VALUES (?, ?, ?, (SELECT count(*) FROM categories WHERE store_id = ?))",
		id, storeID, name, storeID); err != nil {
		e.t.Fatal(err)
	}
	return id
}

func (e *testEnv) personalList(memberID string) string {
	e.t.Helper()
	var id string
	if err := e.db.QueryRow("SELECT id FROM lists WHERE owner_id = ?", memberID).Scan(&id); err != nil {
		e.t.Fatal(err)
	}
	return id
}

// addOp adds an unfiled entry.
func addOp(listID, text string) op {
	return op{OpID: newID(), Type: "entry.add", ID: newID(), ListID: listID, Text: ptr(text)}
}

func entryOp(typ, id string) op {
	return op{OpID: newID(), Type: typ, ID: id}
}

func privacyOp(privacy string) op {
	return op{OpID: newID(), Type: "member.set_privacy", Privacy: privacy}
}

func placeOp(entryID, storeID, categoryID string) op {
	return op{OpID: newID(), Type: "entry.place", ID: entryID, StoreID: storeID, CategoryID: categoryID, NewItemID: newID()}
}

func entryIn(s snapshot, id string) *snapshotEntry {
	if i := slices.IndexFunc(s.Entries, func(x snapshotEntry) bool { return x.ID == id }); i >= 0 {
		return &s.Entries[i]
	}
	return nil
}

func listIn(s snapshot, id string) *snapshotList {
	if i := slices.IndexFunc(s.Lists, func(x snapshotList) bool { return x.ID == id }); i >= 0 {
		return &s.Lists[i]
	}
	return nil
}

func wantRejected(t *testing.T, got []rejection, want ...rejection) {
	t.Helper()
	if !slices.Equal(got, want) {
		t.Errorf("rejected %+v, want %+v", got, want)
	}
}

func TestSyncAddsUnfiledEntry(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	device, _, _ := strings.Cut(token, ".")
	list := e.personalList(alex)
	add := addOp(list, "  burrito \t spice ")
	add.Quantity, add.Note = ptr(" 2  tins "), ptr("")

	w := e.call("POST", "/v1/sync", token, map[string][]op{"ops": {add}})
	for _, want := range []string{`"rejected":[]`, `"stores":[]`} {
		if !strings.Contains(w.Body.String(), want) {
			t.Errorf("no %s in %s", want, w.Body)
		}
	}
	var resp struct {
		Rejected []rejection
		Snapshot snapshot
	}
	e.decode(w, http.StatusOK, &resp)
	s := resp.Snapshot
	want := snapshotEntry{ID: add.ID, ListID: list, Text: "burrito spice", Quantity: "2 tins", CreatedAt: e.now.Format(time.RFC3339)}
	if got := entryIn(s, add.ID); got == nil || !reflect.DeepEqual(*got, want) {
		t.Errorf("entry = %+v, want %+v", got, want)
	}
	if l := listIn(s, list); l == nil || !l.Writable || l.OwnerID == nil || *l.OwnerID != alex {
		t.Errorf("Alex's list = %+v, want it owned by Alex and writable", l)
	}
	if want := (snapshotMe{alex, device, true}); s.Me != want {
		t.Errorf("me = %+v, want %+v", s.Me, want)
	}

	update, empty := entryOp("entry.update", add.ID), entryOp("entry.update", add.ID)
	update.Quantity, update.Note = ptr(""), ptr(" on  sale ")
	noText := addOp(list, "")
	noText.Text = nil
	withStore := addOp(list, "Milk")
	withStore.StoreID = e.store("Grocer")
	longQuantity := addOp(list, "Milk")
	longQuantity.Quantity = ptr(strings.Repeat("9", maxQuantity+1))
	badID := addOp(list, "Milk")
	badID.ID = "not-a-uuid"
	again := addOp(list, "Something else") // an existing id: a no-op
	again.ID = add.ID
	rejected, s := e.sync(token, update, empty, noText, withStore, longQuantity, badID, again)
	wantRejected(t, rejected, rejection{empty.OpID, "invalid"}, rejection{noText.OpID, "invalid"},
		rejection{withStore.OpID, "invalid"}, rejection{longQuantity.OpID, "invalid"}, rejection{badID.OpID, "invalid"})
	want.Quantity, want.Note = "", "on sale"
	if got := entryIn(s, add.ID); got == nil || !reflect.DeepEqual(*got, want) {
		t.Errorf("updated entry = %+v, want %+v", got, want)
	}
	if len(s.Entries) != 1 {
		t.Errorf("%d entries, want 1: %+v", len(s.Entries), s.Entries)
	}
}

func TestResentBatchDoesNotResurrect(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	batch := []op{addOp(e.personalList(alex), "Eggs")}
	id := batch[0].ID

	if _, s := e.sync(token, batch...); entryIn(s, id) == nil {
		t.Fatal("entry not added")
	}
	rejected, s := e.sync(token, entryOp("entry.delete", id))
	wantRejected(t, rejected)
	if entryIn(s, id) != nil {
		t.Fatal("entry not deleted")
	}
	// The response to the first sync was lost, so the client sends it again.
	rejected, s = e.sync(token, batch...)
	wantRejected(t, rejected)
	if entryIn(s, id) != nil {
		t.Error("the resent batch brought the deleted entry back")
	}

	e.now = e.now.Add(91 * 24 * time.Hour)
	e.sync(token)
	var n int
	if err := e.db.QueryRow("SELECT count(*) FROM applied_ops").Scan(&n); err != nil || n != 0 {
		t.Errorf("%d applied ops after 91 days, %v; want 0", n, err)
	}
}

func TestBuyAndUnbuy(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	add := addOp(e.personalList(alex), "Bread")
	e.sync(token, add)

	missing := entryOp("entry.buy", newID())
	rejected, s := e.sync(token, entryOp("entry.buy", add.ID), missing)
	wantRejected(t, rejected, rejection{missing.OpID, "not_found"})
	first := e.now.Format(time.RFC3339)
	if got := entryIn(s, add.ID); got == nil || got.BoughtAt == nil || *got.BoughtAt != first {
		t.Fatalf("bought entry = %+v, want bought_at %s", got, first)
	}

	e.now = e.now.Add(time.Hour)
	_, s = e.sync(token, entryOp("entry.buy", add.ID))
	if got := entryIn(s, add.ID); got == nil || got.BoughtAt == nil || *got.BoughtAt != first {
		t.Errorf("bought again = %+v, want bought_at still %s", got, first)
	}

	_, s = e.sync(token, entryOp("entry.unbuy", add.ID))
	if got := entryIn(s, add.ID); got == nil || got.BoughtAt != nil {
		t.Errorf("unbought entry = %+v, want bought_at null", got)
	}
}

func TestPrivacyEnforced(t *testing.T) {
	e := newTestEnv(t)
	_, admin := e.member("Alex", true) // admins get no exception
	sam, user := e.member("Sam", false)
	samList := e.personalList(sam)
	open, bought := addOp(samList, "Milk"), addOp(samList, "Bread")
	rejected, _ := e.sync(user, open, bought, entryOp("entry.buy", bought.ID))
	wantRejected(t, rejected)

	rejected, _ = e.sync(user, privacyOp("readonly"))
	wantRejected(t, rejected)
	_, s := e.sync(admin)
	if l := listIn(s, samList); l == nil || l.Writable {
		t.Errorf("read-only list for Alex = %+v, want it present and not writable", l)
	}
	alexAdd, alexBuy := addOp(samList, "Beer"), entryOp("entry.buy", open.ID)
	rejected, s = e.sync(admin, alexAdd, alexBuy)
	wantRejected(t, rejected, rejection{alexAdd.OpID, "forbidden"}, rejection{alexBuy.OpID, "forbidden"})
	if got := entryIn(s, open.ID); entryIn(s, alexAdd.ID) != nil || got == nil || got.BoughtAt != nil {
		t.Errorf("Alex changed Sam's read-only list: %+v", s.Entries)
	}
	samAdd := addOp(samList, "Cheese")
	rejected, s = e.sync(user, samAdd)
	wantRejected(t, rejected)
	if entryIn(s, samAdd.ID) == nil {
		t.Error("Sam can't add to his own read-only list")
	}

	rejected, _ = e.sync(user, privacyOp("hidden"))
	wantRejected(t, rejected)
	_, s = e.sync(admin)
	if listIn(s, samList) != nil {
		t.Error("Alex sees Sam's hidden list")
	}
	for _, en := range s.Entries {
		if en.ListID == samList {
			t.Errorf("Alex sees an entry of Sam's hidden list: %+v", en)
		}
	}
	update := entryOp("entry.update", open.ID) // queued while Alex was offline
	update.Note = ptr("skimmed")
	rejected, _ = e.sync(admin, update)
	wantRejected(t, rejected, rejection{update.OpID, "forbidden"})
	var note string
	if err := e.db.QueryRow("SELECT note FROM entries WHERE id = ?", open.ID).Scan(&note); err != nil || note != "" {
		t.Errorf("note of Sam's entry = %q, %v; want unchanged", note, err)
	}
	secret := privacyOp("secret")
	rejected, s = e.sync(user, secret)
	wantRejected(t, rejected, rejection{secret.OpID, "invalid"})
	if l := listIn(s, samList); l == nil || !l.Writable || len(s.Entries) != 3 {
		t.Errorf("Sam's own hidden list = %+v with %d entries, want it writable with 3", l, len(s.Entries))
	}
	if i := slices.IndexFunc(s.Members, func(m snapshotMember) bool { return m.ID == sam }); i < 0 || s.Members[i].Privacy != "hidden" {
		t.Errorf("members = %+v, want Sam still hidden", s.Members)
	}

	rejected, _ = e.sync(user, privacyOp("open"))
	wantRejected(t, rejected)
	_, s = e.sync(admin)
	if l := listIn(s, samList); l == nil || !l.Writable {
		t.Errorf("open list for Alex = %+v, want it writable", l)
	}
	for _, id := range []string{open.ID, bought.ID, samAdd.ID} {
		if entryIn(s, id) == nil {
			t.Errorf("entry %s missing after Sam opened his list", id)
		}
	}
}

func TestFilingLinksToExistingItemIgnoringCase(t *testing.T) {
	e := newTestEnv(t)
	alex, admin := e.member("Alex", true)
	sam, user := e.member("Sam", false)
	store := e.store("Grocer")
	dairy := e.category(store, "Dairy")

	milk := addOp(e.personalList(alex), "Milk")
	place := placeOp(milk.ID, store, dairy)
	n1 := place.NewItemID
	rejected, s := e.sync(admin, milk, place)
	wantRejected(t, rejected)
	if want := []snapshotItem{{n1, "Milk", &store}}; !reflect.DeepEqual(s.Items, want) {
		t.Errorf("items = %+v, want %+v", s.Items, want)
	}
	if got := entryIn(s, milk.ID); got == nil || got.ItemID == nil || *got.ItemID != n1 || got.StoreID == nil || *got.StoreID != store {
		t.Errorf("filed entry = %+v, want item %s in store %s", got, n1, store)
	}
	wantPlacements := []snapshotPlacement{{n1, store, dairy}}
	if !slices.Equal(s.Placements, wantPlacements) {
		t.Errorf("placements = %+v, want %+v", s.Placements, wantPlacements)
	}

	samMilk := addOp(e.personalList(sam), "  milk ")
	samPlace := placeOp(samMilk.ID, store, dairy)
	rejected, s = e.sync(user, samMilk, samPlace)
	wantRejected(t, rejected)
	if got := entryIn(s, samMilk.ID); got == nil || got.ItemID == nil || *got.ItemID != n1 || got.Text != "milk" {
		t.Errorf("Sam's entry = %+v, want text milk linked to item %s", got, n1)
	}
	if len(s.Items) != 1 || !slices.Equal(s.Placements, wantPlacements) {
		t.Errorf("items %+v, placements %+v; want one item and %+v", s.Items, s.Placements, wantPlacements)
	}
	var n int
	if err := e.db.QueryRow("SELECT count(*) FROM items WHERE id = ?", samPlace.NewItemID).Scan(&n); err != nil || n != 0 {
		t.Errorf("%d items %s, %v; want 0", n, samPlace.NewItemID, err)
	}

	// A new_item_id that another item already has is a conflict.
	bread := addOp(e.personalList(alex), "Bread")
	taken := placeOp(bread.ID, store, dairy)
	taken.NewItemID = n1
	rejected, s = e.sync(admin, bread, taken)
	wantRejected(t, rejected, rejection{taken.OpID, "conflict"})
	if got := entryIn(s, bread.ID); got == nil || got.ItemID != nil || got.StoreID != nil || len(s.Items) != 1 {
		t.Errorf("entry %+v, items %+v; want the entry unfiled and one item", got, s.Items)
	}
}

func TestPlaceRejectsForeignCategory(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	grocer, bakery := e.store("Grocer"), e.store("Bakery")
	add := addOp(e.personalList(alex), "Rye")
	foreign := placeOp(add.ID, grocer, e.category(bakery, "Bread"))
	unknown := placeOp(add.ID, grocer, newID())
	noCategory := placeOp(add.ID, grocer, "")

	rejected, s := e.sync(token, add, foreign, unknown, noCategory)
	wantRejected(t, rejected, rejection{foreign.OpID, "invalid"}, rejection{unknown.OpID, "invalid"}, rejection{noCategory.OpID, "invalid"})
	if got := entryIn(s, add.ID); got == nil || got.ItemID != nil || got.StoreID != nil {
		t.Errorf("entry = %+v, want it unfiled", got)
	}
	var n int
	if err := e.db.QueryRow("SELECT count(*) FROM items").Scan(&n); err != nil || n != 0 {
		t.Errorf("%d items, %v; want 0", n, err)
	}
}

func TestBoughtCappedPerList(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	sam, _ := e.member("Sam", false)
	list := e.personalList(alex)
	insert := func(listID string, boughtAt int64) string {
		id := newID()
		if _, err := e.db.Exec("INSERT INTO entries (id, list_id, text, created_at, bought_at) VALUES (?, ?, 'Bread', ?, ?)",
			id, listID, testNow.Unix(), boughtAt); err != nil {
			t.Fatal(err)
		}
		return id
	}
	var ids []string // oldest first
	for i := range 55 {
		ids = append(ids, insert(list, testNow.Unix()+int64(i)))
	}
	samOld := insert(e.personalList(sam), testNow.Unix()-1) // older than all of Alex's: the cap is per list
	open := addOp(list, "Butter")

	_, s := e.sync(token, open)
	bought := 0
	for _, en := range s.Entries {
		if en.ListID == list && en.BoughtAt != nil {
			bought++
		}
	}
	if bought != boughtPerList {
		t.Errorf("%d bought entries on Alex's list, want %d", bought, boughtPerList)
	}
	for i, id := range ids {
		if got := entryIn(s, id) != nil; got != (i >= 5) {
			t.Errorf("entry bought %d s after the first: in snapshot %v, want %v", i, got, i >= 5)
		}
	}
	if entryIn(s, open.ID) == nil || entryIn(s, samOld) == nil {
		t.Error("the open entry or Sam's bought entry is missing")
	}
}

func TestBadOpDoesNotBlockBatch(t *testing.T) {
	e := newTestEnv(t)
	alex, token := e.member("Alex", true)
	list := e.personalList(alex)
	unknown := op{OpID: newID(), Type: "nope"}
	badOpID := addOp(list, "Milk")
	badOpID.OpID = "x"
	good := addOp(list, "Bread")

	rejected, s := e.sync(token, unknown, badOpID, good)
	wantRejected(t, rejected, rejection{unknown.OpID, "invalid"}, rejection{"x", "invalid"})
	if entryIn(s, good.ID) == nil || entryIn(s, badOpID.ID) != nil {
		t.Errorf("entries = %+v, want only Bread", s.Entries)
	}

	noItem := addOp(list, "Eggs")
	noItem.ItemID = newID()
	noStore := placeOp(good.ID, newID(), newID())
	rejected, _ = e.sync(token, noItem, noStore)
	wantRejected(t, rejected, rejection{noItem.OpID, "not_found"}, rejection{noStore.OpID, "not_found"})
}

func TestSyncLimits(t *testing.T) {
	e := newTestEnv(t)
	_, token := e.member("Alex", true)
	ops := make([]op, maxOps+1)
	for i := range ops {
		ops[i] = op{OpID: newID(), Type: "nope"}
	}
	e.wantError(e.call("POST", "/v1/sync", token, map[string][]op{"ops": ops}), http.StatusBadRequest, "invalid")
	big := map[string][]op{"ops": {{OpID: strings.Repeat("x", 2<<20)}}}
	e.wantError(e.call("POST", "/v1/sync", token, big), http.StatusRequestEntityTooLarge, "too_large")

	rejected, _ := e.sync(token, ops[:maxOps]...)
	if len(rejected) != maxOps || slices.ContainsFunc(rejected, func(r rejection) bool { return r.Reason != "invalid" }) {
		t.Errorf("%d rejections, want %d, all invalid", len(rejected), maxOps)
	}
	e.wantStatus(e.call("POST", "/v1/sync", token, map[string]any{}), http.StatusOK)
}

func TestSyncRevokedMidRequest(t *testing.T) {
	e := newTestEnv(t)
	_, admin := e.member("Alex", true)
	sam, user := e.member("Sam", false)
	device, _, _ := strings.Cut(user, ".")
	add := addOp(e.personalList(sam), "Milk")

	// Sam's sync is authenticated, then his device is revoked before its body arrives.
	w := e.callHooked(func() {
		e.wantStatus(e.call("DELETE", "/v1/admin/devices/"+device, admin, nil), http.StatusNoContent)
	}, "POST", "/v1/sync", user, map[string][]op{"ops": {add}})
	e.wantError(w, http.StatusUnauthorized, "unauthorized")
	var entries, applied int
	err := e.db.QueryRow("SELECT (SELECT count(*) FROM entries WHERE id = ?), (SELECT count(*) FROM applied_ops WHERE op_id = ?)",
		add.ID, add.OpID).Scan(&entries, &applied)
	if err != nil || entries != 0 || applied != 0 {
		t.Errorf("%d entries, %d applied ops, %v; want none", entries, applied, err)
	}
}
