# TapPony profile schema and template semantics

Schema version: 1

This file is identical in `TapPony` (iOS) and `TapPonyAndroid`. It is the contract between the two apps: a profile exported on one platform imports on the other, and the same tag reading renders the same request on both. The conformance fixtures in `fixtures/` encode every rule below and run in both test suites (`TapPonyKit` on iOS, `:core` on Android). A change here requires a fixture change and both suites green.

## 1. Profile document

Profiles are JSON documents, one per file, stored in the app container. The on-disk format, the export format, and the cross-platform format are the same thing. Secrets are never inside a profile; the profile refers to them by name.

```json
{
  "schema": 1,
  "id": "4F0C2B1E-7A57-4F5B-9E0B-8C2A1D3E5F60",
  "name": "Home Assistant",
  "request": {
    "method": "POST",
    "url": "http://homeassistant.local:8123/api/webhook/tappony",
    "headers": [
      { "name": "X-Source", "value": "tappony", "secret": false }
    ],
    "body": {
      "type": "json",
      "template": "{\"uid\": \"{uid}\", \"at\": \"{timestamp}\"}",
      "contentType": null,
      "fields": []
    },
    "timeoutSeconds": 15,
    "followRedirects": false,
    "allowLocalHttp": true
  },
  "auth": { "type": "none" },
  "signing": { "enabled": false, "secret": null },
  "tag": {
    "technologies": ["iso14443", "iso15693", "felica"],
    "extendedReads": true,
    "requireNdef": false
  },
  "after": {
    "messageField": null,
    "keepBodies": false,
    "sound": true,
    "haptic": true,
    "queueOffline": false
  }
}
```

Field rules:

- `schema` (int, required). Readers accept any value up to their own version and refuse a higher one with a clear message.
- `id` (string, required). Stable UUID, uppercase canonical form. Never reused.
- `name` (string, required, 1 to 64 characters).
- `request.method`: one of `GET`, `POST`, `PUT`, `PATCH`, `DELETE`.
- `request.url`: a template (section 3), URL context. The scheme and authority must be literal text: no `{` before the first `/` after `://`.
- `request.headers[]`: `name` is literal (RFC 7230 token characters only), `value` is a template in header context. `secret: true` marks the value for masking in every display surface; the value normally contains a `{secret:NAME}` reference.
- `request.body.type`: `json`, `form`, `raw`, or `none`. `template` is used by `json` and `raw`. `fields[]` (`name`, `value`, both templates in form context) is used by `form`. `contentType` overrides the default (`application/json`, `application/x-www-form-urlencoded`, `text/plain; charset=utf-8`). `GET` and `DELETE` send no body regardless of type.
- `request.timeoutSeconds`: 1 to 120, default 15.
- `request.followRedirects`: default false. When true, same scheme and same host only.
- `request.allowLocalHttp`: default false. Required for plain `http://` to a local destination (section 5).
- `auth.type`: `none`, `bearer` (`secret`), `basic` (`username`, `passwordSecret`), `apiKey` (`header`, `secret`). Auth helpers only write a header; they exist so nobody hand-builds base64.
- `signing`: HMAC-SHA256 per section 6, `secret` names the key.
- `tag.technologies`: any of `iso14443`, `iso15693`, `felica`, `iso7816`.
- `after.messageField`: `null`, `json:<dotted.path>` (a field of a JSON response), or `header:<Name>`.
- `after.queueOffline`: default false. When true, a scan whose request got no HTTP response (offline, DNS failure, timeout) is saved on the device and sent later, in scan order, when a connection is back (section 13).
- Unknown fields are ignored on read, so an older build opens a profile written by a newer one with the same schema number.

## 2. Variables

A variable name is `[a-z_]+`. The full set is defined in the planning document, section 7.1, and produced by the variable builder in each core from a `TagReading` plus a send context. Rules that both cores enforce:

- Every variable is a string. Missing or not applicable means the empty string, never an error.
- Values derived from tag content (`payload`, `ndef_text`, `ndef_uri`, `ndef_json`, `ndef_raw`) are truncated to 8192 Unicode code points.
- `{secret:NAME}` resolves from the platform secret store at send time. `NAME` is `[A-Za-z0-9_]+`. An unknown secret is a render error. A rendered secret is masked as `••••` in every display surface.
- An unknown variable name is a render error, and the editor flags it before save.

## 3. Template syntax

- `{name}` inserts a variable. `{name|mod|mod:arg:arg}` applies modifiers left to right.
- A `{` starts a placeholder only when the next character is `a` to `z` or `_` (a variable name, or `secret:`). Every other `{` is literal text. This is what lets a JSON body template be written as plain JSON: `{"uid": "{uid}"}` has one placeholder, and the object braces are literal.
- `}` outside a placeholder is always literal, so nested JSON like `{"a":{"b":1}}` needs no escaping.
- `{{` renders a single literal `{`, for the rare text where a literal brace must be followed by a lowercase letter.
- A placeholder runs to the next `}`. Reaching the end of the template, or another `{`, first is a parse error (unterminated).
- `{ uid }` is literal text, not a placeholder; the editor highlights real placeholders so the difference is visible.
- No conditionals, loops, or expressions. Logic belongs on the server.

## 4. Modifiers

Applied in order, each to the output of the previous one.

| Modifier | Effect |
|---|---|
| `lower`, `upper` | ASCII-only case change |
| `trim` | strip leading and trailing whitespace (space, tab, CR, LF) |
| `b64` | standard Base64 with padding, of the UTF-8 bytes |
| `url` | percent-encode everything except `A-Z a-z 0-9 - . _ ~` (UTF-8 bytes, uppercase hex) |
| `colon` | hex bytes to `AA:BB:CC` form, uppercase |
| `rev` | hex bytes in reverse order, uppercase |
| `dec` | hex bytes as an unsigned big-endian decimal integer |
| `unix` | ISO 8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SS[.fff]Z`) to epoch seconds |
| `slice:A` / `slice:A:B` | code points from A (inclusive) to B (exclusive), clamped to the string |
| `default:TEXT` | TEXT when the value is empty; TEXT is literal and may not contain `|` or `}` |
| `raw` | disable automatic escaping (section 5) where the context allows it |

- Hex-consuming modifiers (`colon`, `rev`, `dec`) accept hex digits in either case with optional `:`, `-`, or space separators. Input that is not an even count of hex digits passes through unchanged.
- `unix` passes non-matching input through unchanged.
- An unknown modifier or a wrong argument count is a parse error.

## 5. Contexts and escaping

After modifiers, every inserted value is escaped for the context the placeholder sits in. Tag content is attacker-controlled input and this is the defense against it.

| Context | Where | Escaping |
|---|---|---|
| URL | `request.url` | percent-encode per the `url` modifier |
| Header | header values, auth helpers | remove CR, LF, and NUL. Always applied, `raw` cannot disable it |
| Form | `body.fields[]` names and values | `application/x-www-form-urlencoded`: unreserved kept, space to `+`, everything else percent-encoded. Applies to the field's literal text too, so `a & b` typed into a value arrives as `a & b` |
| JSON, inside a string literal | `body.template` for `json`, placeholder between quotes | JSON string escaping: `"` `\` and every control character below U+0020 (`\b \f \n \r \t` short forms, `\u00XX` for the rest) |
| JSON, outside a string literal | `body.template` for `json`, placeholder not between quotes | the value becomes one JSON token: a strict JSON number, `true`, `false`, or `null` as-is; empty becomes `null`; anything else becomes a quoted, escaped JSON string |
| Raw | `body.template` for `raw` | none |

Rules:

- A modifier chain containing `url` or `raw` skips the automatic escaping of that placeholder's value in URL, form, and JSON contexts. Header stripping still applies.
- Request assembly (section 9) strips CR, LF, and NUL from every final header value, literal text included.
- A `json` body is parsed after rendering. If it is not valid JSON (RFC 8259, one value, no trailing content) the send fails with a render error. This backstops `raw`.
- A JSON template's own literal text is not validated before rendering; only the rendered result is.
- Strict JSON number: `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`.

## 6. Signing

When `signing.enabled` is true, three headers are added after all other headers are rendered:

```
X-TapPony-Timestamp: <unix seconds of the send time>
X-TapPony-Nonce: <32 lowercase hex characters>
X-TapPony-Signature: sha256=<lowercase hex HMAC-SHA256(key, timestamp + "." + body)>
```

The key is the UTF-8 bytes of the named secret. `body` is the exact rendered body bytes, or the empty string when there is no body. Receivers verify with a constant-time compare and reject timestamps outside their tolerance window.

## 7. Host policy

The validator runs on the rendered URL at send time and on the literal scheme and authority at save time.

- Schemes: `https` and `http` only. Anything else is rejected.
- Userinfo (`user:pass@`) is rejected; credentials go in headers.
- IPv4 literals must be strict dotted quads: four decimal octets 0 to 255, no leading zeros. Any other all-numeric or numeric-looking host (`3232235777`, `0xC0A80101`, `0300.0250.1.1`, `192.168.1`) is rejected on both schemes.
- `https` to any valid host is allowed.
- `http` is allowed only when `allowLocalHttp` is true and the host is local:
  - IPv4 `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `127.0.0.0/8`
  - IPv6 `::1`, `fe80::/10`, `fc00::/7`, and IPv4-mapped forms of the IPv4 ranges above
  - host names ending in `.local` or `.home.arpa`, and single-label host names that are not numeric
- `http` to a local host with `allowLocalHttp` false is rejected with a distinct reason, so the editor can offer the toggle.
- Host names compare case-insensitively; a trailing dot is removed before checks.

## 8. UID canonical order

`{uid}` is the order printed by NXP TagInfo and the NFC Forum.

- ISO 14443-A: UID0 (manufacturer byte) first, as both platforms report it.
- ISO 15693: `E0` first. If the reported identifier ends in `E0` and does not start with it, the core reverses it. This covers Android's transmission order and whatever Core NFC reports, without a platform flag.
- FeliCa: the IDm as reported.
- `{random_uid}` is `true` for a 4-byte NFC-A identifier whose first byte is `08`.
- `{manufacturer}` comes from the ISO/IEC 7816-6 IC manufacturer code: UID0 for 7-byte NFC-A identifiers, the byte after `E0` for ISO 15693, `Sony` for FeliCa.

## 9. Request assembly

Given a profile, the variables for one scan, the secret store, and the send time, both cores assemble the same request:

1. The URL template must pass the save-time rule (section 7). It is rendered in URL context and the result goes through the host policy with the profile's `allowLocalHttp`. A rejection fails the send with `hostPolicy:<reason>`.
2. Headers, in this order: the profile's headers (header context), then the auth helper's header (`Authorization: Bearer <secret>`, `Authorization: Basic base64(username:password)`, or `<header>: <secret>`), then `Content-Type` when there is a body and no header named `content-type` in any case already exists, then the three signing headers when signing is on. Header names must be RFC 7230 tokens. Every final header value has CR, LF, and NUL removed.
3. Body: none for `GET`, `DELETE`, and type `none`. `json` and `raw` render `template` in their contexts. `form` renders each field's name and value in form context and joins them as `name=value` pairs with `&`, in order.
4. Signing (section 6) covers the exact body string, or the empty string when there is no body. The nonce header carries the same value as `{nonce}`.

Errors are reported as `hostPolicy:<reason>`, `urlTemplate:<reason>`, `template:<code>`, `badHeaderName`, `badMethod`, `badAuth`, or `badBodyType`. Template codes: `unterminated`, `badName`, `unknownModifier`, `badModifierArgs`, `unknownVariable`, `unknownSecret`, `invalidJsonBody`.

## 10. Variable builder and NDEF

- Times: `{timestamp}` and `{sent_at}` are UTC, `YYYY-MM-DDTHH:MM:SS.mmmZ`. `{timestamp_local}` is the same instant in the device time zone with a `±HH:MM` offset. `{unix}` is whole seconds, floored. `{tz}` is the IANA zone name.
- `{payload}`: the first record decoded. A Text record (TNF 1, type `T`) gives its text; a URI record (TNF 1, type `U`) gives the full URI with its prefix code expanded (NFC Forum URI RTD table, codes `0x00` to `0x23`; any other code expands to nothing); an absolute-URI record (TNF 3) gives its type field. Anything else gives the Base64 of the record payload.
- Text records: status byte bit 7 selects UTF-16 (BOM honored, big-endian without one) over UTF-8; bits 0 to 5 are the language code length.
- `{ndef_text}` and `{ndef_uri}` are the first Text and first URI (well-known or absolute) records anywhere in the message.
- `{ndef_json}`: a compact JSON array, one object per record, keys in this order: `tnf` (number), `type` (the type bytes as Latin-1 text), `id` (Base64), `payload` (Base64), then `text` or `uri` when the record decodes as one. No whitespace.
- `{ndef_raw}`: Base64 of the NDEF message re-encoded from its records (NFC Forum NDEF 1.0: MB on the first record, ME on the last, SR when the payload is under 256 bytes, IL when there is an ID). Both platforms encode it themselves so the bytes match.
- `{token}`: the `k` query parameter of `{ndef_uri}` when it is an `https://tappony.app/t/...` launch link, otherwise empty.
- `{idm}` is the UID for FeliCa and empty otherwise; `{pupi}` is the UID for ISO 14443-B and empty otherwise.
- Hex-valued variables (`signature`, `atqa`, `sak`, `dsfid`, `afi`, `pmm`, `system_code`, `historical_bytes`, `application_data`) are uppercase with no separators.

## 11. Response message

`after.messageField` picks one piece of the server's reply to show on the Scan screen (and, later, to speak aloud):

- `null` or empty: nothing.
- `header:<Name>`: the first response header with that name, compared case-insensitively.
- `json:<path>`: the response body parsed as strict JSON, then walked by `.`-separated segments. A segment names an object member, or indexes an array when it is a plain non-negative integer with no leading zero. `json:` with an empty path means the whole body.
- The value found becomes text: a string as-is, `true`/`false`, an integer without a decimal point, other numbers in the platform's shortest form, and objects or arrays as compact JSON with keys in the order the server sent them. JSON `null`, a missing member, an out-of-range index, or a body that is not valid JSON all mean no message.
- The result is cut to 200 code points. It is shown as plain text, never rendered or followed.

## 12. History CSV

History exports as RFC 4180 CSV with CRLF line endings, one header row, then one row per scan, oldest first:

```
time,profile,uid,chip,tag_type,outcome,status,latency_ms,error
```

- `time` is the scan time in the `{timestamp}` format. `status` and `latency_ms` are empty when there was no HTTP response.
- `outcome` is `not_sent` when the request was never built (host policy, template, or secret error), `network_error` when it was built but no HTTP response came back, `ok` for 2xx, and `http_error` for any other status.
- A field starting with `=`, `+`, `-`, `@`, tab, or CR gets a leading `'` so spreadsheet apps don't run it as a formula. Profile names and error text can come from anywhere.
- A field is quoted when it contains a comma, a double quote, CR, or LF, or starts or ends with a space. Quotes inside are doubled.
- Request and response bodies are never exported, even when a profile keeps them.

## 13. Offline queue

When `after.queueOffline` is on and a send ends with no HTTP response, the scan is queued instead of logged as a network error.

- The queue stores the profile id and the scan's variables, never the rendered request, so no secret is written to the queue. The request is rebuilt from the current profile and secrets when it is finally sent.
- On resend, `{sent_at}` and the signing timestamp are the real send time. `{timestamp}`, `{seq}`, and `{nonce}` keep their scan-time values, so a receiver can drop a duplicate if an earlier attempt did arrive before the connection failed.
- Items go out oldest first. The first item that still gets no response stops the run; the rest wait for the next attempt.
- Any HTTP response, success or not, ends an item and writes it to history with its original scan time. So does a build error (for example, a secret deleted in the meantime), logged as `not_sent`.
- An item still unsent 24 hours after its scan is dropped and logged as `network_error`. An item whose profile was deleted is dropped and logged as `not_sent`.

