# PocketLarder API, version 1

This is the contract between a PocketLarder server and its clients. It covers
pairing a device with an invite, signing out and the admin area.

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
- **Body size.** A request body may be at most 64 KiB. A larger one gives
  413 `too_large`. A body that isn't valid JSON, has a field of the wrong type,
  has a field the endpoint doesn't know, or is empty gives 400 `invalid`.
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
| 400 | `invalid` | The body is malformed, or a value in it isn't allowed. |
| 401 | `unauthorized` | The device token is missing, malformed or revoked. Treat the device as signed out. |
| 401 | `invalid_invite` | The invite code can't be redeemed. |
| 403 | `forbidden` | The request needs an admin. |
| 404 | `not_found` | The member or device doesn't exist, or the id isn't a lowercase UUID. |
| 409 | `conflict` | Another member already has that name. |
| 409 | `last_admin` | The request would leave the household without an admin. |
| 413 | `too_large` | The body is over 64 KiB. |
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
