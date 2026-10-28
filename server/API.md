# PocketLarder API, version 1

This is the contract between a PocketLarder server and its clients. It covers
pairing a device with an invite, syncing the household's lists, signing out and
the admin area.

## Basics

- **Base URL.** The server's public URL, for example `https://lists.example.com`.
  It is the same URL an invite URL carries in its `server` parameter. Every
  endpoint is under `/v1`.
- **JSON.** Request and response bodies are JSON. Endpoints that take a body
  need a JSON object: send `{}` when there is nothing to say. Responses with a
  body carry `Content-Type: application/json` and `Cache-Control: no-store`.
- **Authentication.** Every endpoint except `POST /v1/invites/redeem` needs the
  device token in this header:

  ```http
  Authorization: Bearer <token>
  ```

  A missing, malformed or revoked token gives 401 `unauthorized`. The token is
  checked before anything else about the request, and on admin endpoints admin
  rights (403 `forbidden`) are checked next, before the path and the body.
- **Body size.** A request body may be at most 64 KiB, or 1 MiB for
  `POST /v1/sync`. A larger one gives 413 `too_large`. A body that isn't valid
  JSON, has a field of the wrong type, has a field the endpoint doesn't know,
  or is empty gives 400 `invalid`.
- **IDs** are lowercase UUIDs such as `3f367fb6-d649-4507-8a37-a0813a0cdfb7`.
  An id in a path that isn't in this form gives 404 `not_found`.
- **Timestamps** are RFC 3339 strings in UTC without fractions, such as
  `2026-10-27T10:00:00Z`.
- **Tokens and invite codes** are opaque strings. Don't parse them.

## Errors

Every error with a JSON body has this form, and the body never carries
anything else:

```json
{"error": "<code>"}
```

| Status | Code | Meaning |
|---|---|---|
| 400 | `invalid` | The body is malformed, a value in it isn't allowed, or a sync request has more than 500 ops. |
| 401 | `unauthorized` | The device token is missing, malformed or revoked. Treat the device as signed out. |
| 401 | `invalid_invite` | The invite code can't be redeemed. |
| 403 | `forbidden` | The request needs an admin. |
| 404 | `not_found` | The member or device doesn't exist, or the id isn't a lowercase UUID. |
| 409 | `conflict` | Another member already has that name. |
| 409 | `last_admin` | The request would leave the household without an admin. |
| 413 | `too_large` | The body is over 64 KiB, or over 1 MiB for `POST /v1/sync`. |
| 429 | `rate_limited` | Too many redemption attempts. Try again in a minute. |
| 500 | `internal` | The server failed. Nothing about the cause is sent. |

A path or method the API doesn't have gets a plain-text 404 or 405, not a JSON
error.

## Invites

An invite lets one device sign in as one member. Each invite is bound to a
member: redeeming it adds a device for that member.

- **Invite URL.** An invite is handed over as this URL:

  ```
  pocketlarder://invite?server=<URL-encoded public URL>&code=<code>
  ```

  For example
  `pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio`.
  The same string is the QR code payload and the copyable text code. A client
  takes `server` as the base URL and sends `code` to `POST /v1/invites/redeem`.
- **Single-use and short-lived.** An invite can be redeemed once, and it
  expires 24 hours after it was created.
- **One answer for every bad code.** An unknown, used, expired or revoked code
  and a code with the wrong secret all give the same 401 `invalid_invite`.
- **Rate limit.** The whole server accepts 10 redemption attempts per minute,
  counted in fixed one-minute windows. Every attempt counts, successful ones
  included. Further attempts get 429 `rate_limited`. The limit is checked
  before the request is read, so a 429 says nothing about the code.
- **Device names.** The client names the device when it redeems an invite, and
  the name never makes redemption fail. The server cleans it:
  - Invisible and control characters are dropped.
  - Runs of whitespace collapse to one space, and leading and trailing
    whitespace is removed.
  - The name is cut to 64 characters (Unicode code points).
  - A name with nothing left becomes `"Unnamed device"`.
- **Revoking invites doesn't sign anyone out.** `POST /v1/invites/revoke`
  deletes invites that haven't been redeemed. Devices that already paired stay
  signed in. To sign one out, an admin uses `DELETE /v1/admin/devices/{id}`.

## Known limits

Version 1 accepts these. Each has an issue for a later fix.

- **Anyone can hold up pairing.** The redemption limit is one budget for the
  whole server. A client sending 10 bogus codes a minute makes every real
  redemption get 429 `rate_limited`
  ([#13](https://github.com/vrob01/PocketLarder/issues/13)).
- **Signed-in requests aren't rate-limited.** Only `POST /v1/invites/redeem`
  is. A paired device, or anyone holding its token, can call every other
  endpoint as fast as the server answers
  ([#14](https://github.com/vrob01/PocketLarder/issues/14)).
- **Signing a device out doesn't revoke invites.** Unredeemed invites stay
  valid until they expire, including any the device created before it was
  signed out. When signing out a lost or stolen device, an admin also calls
  `POST /v1/invites/revoke` with that device's `member_id`
  ([#15](https://github.com/vrob01/PocketLarder/issues/15)).

## Endpoints

| Method and path | Auth |
|---|---|
| `POST /v1/invites/redeem` | none, rate-limited |
| `POST /v1/invites` | member |
| `POST /v1/invites/revoke` | member |
| `POST /v1/signout` | member |
| `POST /v1/sync` | member |
| `GET /v1/admin/members` | admin |
| `PATCH /v1/admin/members/{id}` | admin |
| `DELETE /v1/admin/members/{id}` | admin |
| `DELETE /v1/admin/devices/{id}` | admin |

### POST /v1/invites/redeem

Redeems an invite code and pairs this device. No `Authorization` header.

```http
POST /v1/invites/redeem
Content-Type: application/json

{"code": "fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio", "device_name": "Phone"}
```

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"token": "902ce6e8-8fd1-4c91-80f4-de517bc0699f.5ScBr-9sICpv5jcJvuCpvsC_aggYC6337nbb9gHcyTs", "member_id": "7317f087-10f7-4bd2-b23e-c5d5726c04bd", "device_id": "902ce6e8-8fd1-4c91-80f4-de517bc0699f"}
```

The token is sent only this once. The server keeps only a hash of it, so a
lost token can't be recovered: the device needs a new invite. A token doesn't
expire. It stops working when the device signs out, when an admin revokes the
device, or when the member is removed.

Errors: 400 `invalid`, 401 `invalid_invite`, 413 `too_large`,
429 `rate_limited`.

### POST /v1/invites

Creates an invite. The body takes one of three forms:

- `{}` invites another device for the caller's own member. Any member may do
  this.
- `{"member_id": "<id>"}` invites a device for that member. Admins only.
- `{"new_member_name": "<name>"}` creates a new member, with their personal
  list, and invites their first device. The new member isn't an admin. Admins
  only.

A field counts as given when it is in the body, even as `""`. A non-admin who
gives either field gets 403 `forbidden`, and giving both gives 400 `invalid`.

A new member's name is cleaned first: Unicode compatibility normalisation
(NFKC), leading and trailing whitespace removed and runs of whitespace
collapsed to one space. What's left must be 1 to 100 characters with no
control or invisible characters, or the request gets 400 `invalid`. Names are
unique ignoring case, so a name another member already has, in any case, gets
409 `conflict`.

```http
POST /v1/invites
Authorization: Bearer <token>
Content-Type: application/json

{"new_member_name": "Sam"}
```

```http
HTTP/1.1 201 Created
Content-Type: application/json

{"url": "pocketlarder://invite?server=https%3A%2F%2Flists.example.com&code=fdd4efb3-cf5b-44e7-bec4-94df8e478f5f.ArBLMeKiOpJu5jbcasIRDr8-zlqlbdWCoIfZ9EsLPio", "expires_at": "2026-10-28T09:00:00Z", "member_id": "7317f087-10f7-4bd2-b23e-c5d5726c04bd"}
```

`url` is the invite URL to show as a QR code and as text. `member_id` is the
member the invite signs in.

Errors: 400 `invalid`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`
(no member with that `member_id`), 409 `conflict`, 413 `too_large`.

### POST /v1/invites/revoke

Deletes a member's unredeemed invites, so an invite sent to the wrong person
can't be used. The body is `{}` for the caller's own member, or
`{"member_id": "<id>"}` for another member, which needs an admin. Paired
devices stay signed in.

```http
POST /v1/invites/revoke
Authorization: Bearer <token>
Content-Type: application/json

{"member_id": "7317f087-10f7-4bd2-b23e-c5d5726c04bd"}
```

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"revoked": 1}
```

`revoked` is how many invites were deleted, expired ones included.

Errors: 400 `invalid`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`,
413 `too_large`.

### POST /v1/signout

Signs this device out: the server deletes it, and its token stops working.
There is no request body.

```http
POST /v1/signout
Authorization: Bearer <token>
```

```http
HTTP/1.1 204 No Content
```

Errors: 401 `unauthorized`.

### GET /v1/admin/members

Lists every member with their devices. Admins only.

```http
GET /v1/admin/members
Authorization: Bearer <token>
```

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "members": [
    {
      "id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7",
      "name": "Alex",
      "is_admin": true,
      "privacy": "open",
      "pending_invites": 0,
      "devices": [
        {"id": "41c68cb8-2f63-4d34-92b5-26d3521f739d", "name": "Tablet", "created_at": "2026-10-20T08:15:00Z", "last_seen_at": "2026-10-27T10:00:00Z"}
      ]
    },
    {
      "id": "7317f087-10f7-4bd2-b23e-c5d5726c04bd",
      "name": "Sam",
      "is_admin": false,
      "privacy": "hidden",
      "pending_invites": 0,
      "devices": [
        {"id": "902ce6e8-8fd1-4c91-80f4-de517bc0699f", "name": "Phone", "created_at": "2026-10-27T09:30:00Z", "last_seen_at": "2026-10-27T09:45:12Z"}
      ]
    },
    {
      "id": "850c282d-bf55-4b61-acbe-afcce2a7a6c4",
      "name": "Robin",
      "is_admin": false,
      "privacy": "open",
      "pending_invites": 1,
      "devices": []
    }
  ]
}
```

- Members and each member's devices are ordered by id. The order means
  nothing else.
- `privacy` is the member's personal list setting: `open`, `readonly` or
  `hidden`.
- `pending_invites` counts the member's invites that are neither redeemed nor
  expired. A member who was invited but never paired has `"devices": []` and
  can be removed like any other member.
- `last_seen_at` is the time of the device's last authenticated request.

Errors: 401 `unauthorized`, 403 `forbidden`.

### PATCH /v1/admin/members/{id}

Makes a member an admin, or removes their admin rights. Admins only. The body
must have `is_admin`, a boolean. The change applies from the member's next
request.

```http
PATCH /v1/admin/members/7317f087-10f7-4bd2-b23e-c5d5726c04bd
Authorization: Bearer <token>
Content-Type: application/json

{"is_admin": true}
```

```http
HTTP/1.1 204 No Content
```

Errors: 400 `invalid` (no `is_admin`, or not a boolean), 401 `unauthorized`,
403 `forbidden`, 404 `not_found`, 409 `last_admin` (the only admin can't
remove their own admin rights), 413 `too_large`.

### DELETE /v1/admin/members/{id}

Removes a member. Admins only. Their devices are signed out, and their
invites, personal list and its entries are deleted. An admin may remove
themselves when another admin is left.

```http
DELETE /v1/admin/members/850c282d-bf55-4b61-acbe-afcce2a7a6c4
Authorization: Bearer <token>
```

```http
HTTP/1.1 204 No Content
```

Errors: 401 `unauthorized`, 403 `forbidden`, 404 `not_found`, 409 `last_admin`
(the only admin can't be removed).

### DELETE /v1/admin/devices/{id}

Signs a device out by deleting it. Its token stops working. Admins only. This
works for any device, the caller's own included.

```http
DELETE /v1/admin/devices/902ce6e8-8fd1-4c91-80f4-de517bc0699f
Authorization: Bearer <token>
```

```http
HTTP/1.1 204 No Content
```

Errors: 401 `unauthorized`, 403 `forbidden`, 404 `not_found`.

## Sync

A client keeps a full local copy of everything its member may see, and works
on that copy offline. Every change the member makes is an op: the client
applies it to its copy, queues it, and sends the queue to `POST /v1/sync`. The
server applies the ops in one transaction and answers with a snapshot of
everything the member may see after them.

### POST /v1/sync

Applies queued ops and returns a snapshot. Any member.

The body is `{"ops": [...]}` with at most 500 ops. A longer queue goes in
several requests, in queue order, each sent after the one before got its
response. `{"ops": []}` applies nothing and just fetches a snapshot. Each op
carries an `op_id`, a `type` and the fields its type lists under
[Operations](#operations). Send no other fields: one the API doesn't know
makes the whole request 400 `invalid`.

```http
POST /v1/sync
Authorization: Bearer <token>
Content-Type: application/json

{"ops": [
  {"op_id": "c1556fb5-68a1-4d4b-874c-0a7d69c81dcc", "type": "entry.add", "id": "ae94504a-2040-4e7b-bfea-d548f7d2f25e", "list_id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "text": "Burrito spice", "quantity": "2"},
  {"op_id": "dd597075-5860-45fb-91e7-bd55836bf114", "type": "entry.buy", "id": "f4c9ecca-9050-43c7-b9af-3533815f47b4"}
]}
```

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "rejected": [
    {"op_id": "dd597075-5860-45fb-91e7-bd55836bf114", "reason": "not_found"}
  ],
  "snapshot": {
    "me": {"member_id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7", "device_id": "41c68cb8-2f63-4d34-92b5-26d3521f739d", "is_admin": true},
    "members": [
      {"id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7", "name": "Alex", "is_admin": true, "privacy": "open"},
      {"id": "7317f087-10f7-4bd2-b23e-c5d5726c04bd", "name": "Sam", "is_admin": false, "privacy": "hidden"}
    ],
    "lists": [
      {"id": "25662915-e490-432f-9165-23d1318ebafd", "owner_id": null, "name": "Party", "color": "teal", "archived": false, "writable": true},
      {"id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "owner_id": "3f367fb6-d649-4507-8a37-a0813a0cdfb7", "name": null, "color": null, "archived": false, "writable": true}
    ],
    "stores": [
      {"id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "name": "Corner shop", "position": 0}
    ],
    "categories": [
      {"id": "5cb64f0a-df16-48a1-bb51-7896414bc438", "store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "name": "Dairy", "position": 0}
    ],
    "items": [
      {"id": "6c052e92-3357-493b-9e07-65ae1fb0802f", "name": "Milk", "default_store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0"}
    ],
    "placements": [
      {"item_id": "6c052e92-3357-493b-9e07-65ae1fb0802f", "store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "category_id": "5cb64f0a-df16-48a1-bb51-7896414bc438"}
    ],
    "entries": [
      {"id": "785a8c25-38e6-4526-80ca-290927283c0f", "list_id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "item_id": "6c052e92-3357-493b-9e07-65ae1fb0802f", "text": "Milk", "quantity": "", "note": "", "store_id": "56058b71-5fd8-4e28-8784-5a26ddd960c0", "created_at": "2026-10-26T18:30:00Z", "bought_at": "2026-10-27T09:12:40Z"},
      {"id": "ae94504a-2040-4e7b-bfea-d548f7d2f25e", "list_id": "8832e435-0cdc-4290-b837-bbcc46e65f42", "item_id": null, "text": "Burrito spice", "quantity": "2", "note": "", "store_id": null, "created_at": "2026-10-27T10:00:00Z", "bought_at": null}
    ]
  }
}
```

`rejected` lists the ops that changed nothing, each with its `op_id` and a
`reason`: `invalid`, `forbidden`, `not_found` or `conflict`. It is `[]` when
every op applied.

Errors: 400 `invalid` (a malformed body or more than 500 ops),
401 `unauthorized`, 413 `too_large` (over 1 MiB). On any error nothing in the
request was applied.

### The snapshot

Every array is present, and `[]` when empty.

- `me`: the caller's `member_id` and `device_id`, and `is_admin`.
- `members`: every member of the household, with `id`, `name`, `is_admin` and
  `privacy` (`open`, `readonly` or `hidden`). Members who were invited but
  never paired are included.
- `lists`: the lists the caller sees, with `id`, `owner_id`, `name`, `color`,
  `archived` and `writable`. `owner_id` is the member whose personal list it
  is, or `null` for a shared list. `name` and `color` are `null` on personal
  lists. `archived` and `writable` are booleans.
- `stores` (`id`, `name`, `position`), `categories` (`id`, `store_id`, `name`,
  `position`), `items` (`id`, `name`, `default_store_id`) and `placements`
  (`item_id`, `store_id`, `category_id`): the household catalog, all of it, for
  every member. An item's `default_store_id` is `null` until it has one. A
  placement is the item's category in that store.
- `entries`: `id`, `list_id`, `item_id`, `text`, `quantity`, `note`,
  `store_id`, `created_at` and `bought_at`. `item_id` and `store_id` are `null`
  until the entry is filed. `quantity` and `note` are `""` when not set.
  `bought_at` is `null` while the entry is open.

Stores and categories are ordered by `position`, then `id`. Placements are
ordered by `item_id`, then `store_id`. Everything else is ordered by `id`, and
that order means nothing else.

What a member sees:

- Every shared list, archived ones included, their own personal list, and
  every other member's personal list unless its owner set it to `hidden`.
- A hidden list and its entries, recently bought ones included, never reach
  another member's device. Admins get no exception.
- `writable` says whether the caller's ops on the list apply. It is `true` for
  shared lists, the caller's own list and other members' `open` lists, and
  `false` for `readonly` lists. Ops on a list that isn't writable, hidden ones
  included, are rejected `forbidden`.
- Every open entry of each list the member sees, plus the newest 50 bought
  entries of each of those lists. Older bought entries stay on the server but
  aren't sent.

**Not filed yet.** A client shows an entry under "Not filed yet" when it has
no `item_id`, no `store_id`, or no placement for its (`item_id`, `store_id`).

### Operations

Every op has an `op_id`, a lowercase UUID the client makes for it, and a
`type`. An op whose `op_id` isn't a lowercase UUID, or whose `type` isn't one
below, is rejected `invalid`. The ids a client creates, the `id` of
`entry.add`, `list.create`, `store.create` and `category.create` and the
`new_item_id` of `entry.place`, are lowercase UUIDs too.

Text is cleaned before it is stored: Unicode normalisation (NFC), leading and
trailing whitespace removed and runs of whitespace collapsed to one space.
What's left must not be empty, must have no control characters, and must fit
its limit in characters (Unicode code points): `text` and `name` 100,
`quantity` 32 and `note` 200. A value that fails is `invalid`.

Fields marked `?` are optional. Every entry op except `entry.add` gives
`not_found` when the entry doesn't exist and `forbidden` when its list isn't
writable. Any member may run the list, store, category and item ops. In
them, an id that names something that doesn't exist, malformed ones
included, is `not_found`.

#### entry.add

Fields: `id`, `list_id`, `item_id?`, `text?`, `store_id?`, `quantity?`,
`note?`.

Adds an open entry to the list.

- With `item_id`: the entry's `text` is the item's name, and a `text` in the
  op is ignored. Its store is `store_id`, or else the item's default store.
- Without `item_id`: `text` is required, and the entry is unfiled, with no
  item and no store. Giving `store_id` is `invalid`.
- `quantity` and `note` are `""` when absent or `""`.
- An `id` that an entry already has makes the op do nothing, without a
  rejection.

Rejected: `not_found` (the list, the item or the store doesn't exist),
`forbidden` (the list isn't writable), `invalid` (a bad `id`, no `text`
without `item_id`, a `store_id` without `item_id`, or a value that fails
cleaning).

#### entry.update

Fields: `id`, `quantity?`, `note?`.

Sets each field that is present. `""` clears it.

Rejected: `not_found`, `forbidden`, `invalid` (neither field, or a value that
fails cleaning).

#### entry.buy

Fields: `id`.

Crosses the entry off. `bought_at` is the time the first `entry.buy` reached
the server, and buying the entry again keeps that time.

Rejected: `not_found`, `forbidden`.

#### entry.unbuy

Fields: `id`.

Makes the entry open again: `bought_at` becomes `null`.

Rejected: `not_found`, `forbidden`.

#### entry.delete

Fields: `id`.

Deletes the entry.

Rejected: `not_found`, `forbidden`.

#### entry.place

Fields: `id`, `store_id`, `category_id?`, `new_item_id?`.

Files an entry in a store, or moves it to another store.

- `store_id` must exist. A `category_id` must be a category of that store.
- An entry with no item needs `category_id` and `new_item_id`. If an item has
  the entry's text as its name, ignoring case, the entry links to that item.
  Otherwise a new item is created with `new_item_id` as its id, the entry's
  text as its name and `store_id` as its default store.
- On an entry that has an item, `new_item_id` is ignored.
- Then the entry's store becomes `store_id`. If `category_id` is given, it
  becomes the item's placement in that store. An item without a default store
  gets `store_id`.

Rejected: `not_found` (the entry or the store doesn't exist), `forbidden`,
`invalid` (a `category_id` that doesn't exist or is in another store, or, on
an entry with no item, a missing `category_id` or a bad `new_item_id`),
`conflict` (`new_item_id` is already another item's id).

#### member.set_privacy

Fields: `privacy`.

Sets the privacy of the caller's own personal list:

- `open`: other members see it and may change it.
- `readonly`: other members see it, and their ops on it are rejected
  `forbidden`.
- `hidden`: other members don't get the list or its entries at all, and their
  ops on it are rejected `forbidden`.

The owner always sees and changes their own list. Hidden covers the list and
its entries, not the catalog: an item created by filing an entry from a hidden
list is in every member's snapshot, like the rest of the catalog.

Rejected: `invalid` (anything but `open`, `readonly` or `hidden`).

#### list.create

Fields: `id`, `name`, `color`.

Creates a shared list, not archived. `color` is one of `red`, `orange`,
`yellow`, `green`, `teal`, `blue`, `purple`, `pink` or `gray`.

Rejected: `invalid` (a bad `id`, a missing `name` or one that fails cleaning,
or a missing `color` or one not in the list above), `conflict` (`id` is
already a list's id).

#### list.update

Fields: `id`, `name?`, `color?`, `archived?`.

Sets each field that is present on a shared list. `archived` is a boolean. An
archived list stays in every member's snapshot, with `archived` true.

Rejected: `not_found` (the list doesn't exist), `forbidden` (a personal list,
the caller's own included), `invalid` (no field, a `name` that fails
cleaning, or a `color` not in the list under `list.create`).

#### store.create

Fields: `id`, `name`.

Creates a store after all the others: its `position` is one more than the
highest, or 0 for the first store.

Rejected: `invalid` (a bad `id`, or a missing `name` or one that fails
cleaning), `conflict` (`id` is already a store's id).

#### store.rename

Fields: `id`, `name`.

Sets the store's name.

Rejected: `not_found`, `invalid` (a missing `name` or one that fails
cleaning).

#### store.delete

Fields: `id`.

Deletes the store, its categories and every placement in it. Items that had
it as their default store have none, and entries filed in it lose their
`store_id`. The entries themselves stay, keep their item and text, and show
under "Not filed yet".

Rejected: `not_found`.

#### store.reorder

Fields: `ids`.

Reorders the stores. The stores listed in `ids` take positions from 0 up in
the order given, and every other store follows them in its previous order, so
the positions run from 0 to one less than the number of stores. Ids that
aren't a store's are ignored, and an id listed twice counts where it first
appears. An empty or absent `ids` keeps the order and only renumbers.
Unlisted stores follow instead of being dropped, so that a stale client can't
knock out a store it has never heard of.

Never rejected.

#### category.create

Fields: `id`, `store_id`, `name`.

Creates a category after the store's others: its `position` is one more than
the highest in that store, or 0 for the store's first category.

Rejected: `not_found` (the store doesn't exist), `invalid` (a bad `id`, or a
missing `name` or one that fails cleaning), `conflict` (`id` is already a
category's id).

#### category.rename

Fields: `id`, `name`.

Sets the category's name.

Rejected: `not_found`, `invalid` (a missing `name` or one that fails
cleaning).

#### category.delete

Fields: `id`.

Deletes the category and the placements that use it. Entries keep their
`item_id` and `store_id`, and an entry whose item lost its placement in that
store shows under "Not filed yet".

Rejected: `not_found`.

#### category.reorder

Fields: `store_id`, `ids`.

Reorders the store's categories by the same rule as `store.reorder`, within
that store only. A category of another store is an unknown id here, and the
other store's order doesn't change.

Rejected: `not_found` (the store doesn't exist).

#### item.update

Fields: `id`, `name?`, `default_store_id?`.

Sets each field that is present. `default_store_id` `""` clears the default
store. A new `name` must not be another item's name, ignoring case; changing
only the case of the item's own name is fine. Renaming an item doesn't change
the `text` of its entries.

Rejected: `not_found` (the item or a non-empty `default_store_id` doesn't
exist), `invalid` (neither field, or a `name` that fails cleaning),
`conflict` (another item has that name, ignoring case).

#### item.place

Fields: `id`, `store_id`, `category_id`.

Makes `category_id` the item's placement in `store_id`, replacing the one it
had there. The item's default store and its entries don't change.

Rejected: `not_found` (the item or the store doesn't exist), `invalid` (a
missing `category_id`, or one that doesn't exist or is in another store).

#### item.delete

Fields: `id`.

Deletes the item and its placements. Its entries lose their `item_id` but keep
their `text` and `store_id`, and show under "Not filed yet".

Rejected: `not_found`.

### Rules

- **Ops are idempotent by `op_id`.** The server remembers every `op_id` it
  has applied for 90 days, and skips an op whose `op_id` it remembers, without
  a rejection. A batch sent again after a lost response therefore changes
  nothing twice, and doesn't bring back an entry deleted since.
- **A 200 consumes every op in the request.** Each op was applied, skipped as
  a repeat or rejected. The client drops all of them from its queue, whether
  or not they are in `rejected`. A rejected op's effect isn't in the snapshot,
  so it leaves the client's copy when the snapshot replaces it.
- **Any other status applies nothing.** The client keeps the batch and sends
  it again later, unchanged. A batch within the limits above never gets 400 or
  413, and a 401 means the device is signed out.
- **Ops apply in the order they arrive**, within a request and across
  requests, and the last one wins: when two members change the same thing,
  the change that reaches the server last stays.
- **Each snapshot replaces the client's whole local copy.** Anything not in it
  is gone from the client. This is how a list that was just hidden, with its
  entries, leaves other members' devices.

**The client's duty.** The server can't see a client's queue. The client keeps
every op the server hasn't acknowledged with a 200, both those still queued
and those in a request awaiting its response, and re-applies them, in queue
order, on top of every snapshot it receives. This way a sync never undoes a
local change: an entry crossed off offline stays crossed off until its
`entry.buy` reaches the server.
