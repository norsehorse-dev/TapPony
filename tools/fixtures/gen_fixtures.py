"""Generate shared/fixtures/*.json from the reference implementation.

Hand-checked expectations are asserted inline (CHECK) so a bug in ref.py cannot
silently become the contract.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import ref

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "fixtures")
os.makedirs(OUT, exist_ok=True)

VARS = {
    "uid": "04A27F1B5E8000",
    "uid_colon": "04:A2:7F:1B:5E:80:00",
    "uid_len": "7",
    "chip": "NTAG215",
    "tag_type": "mifare_ultralight",
    "payload": "Kitchen \"door\"\n\ttab\\slash",
    "ndef_text": "héllo wörld ✓",
    "ndef_uri": "https://tappony.app/t/abc?k=1&x=2",
    "timestamp": "2026-09-25T22:30:05.123Z",
    "seq": "42",
    "counter": "",
    "random_uid": "false",
    "profile": "Front door",
    "device_label": "",
    "control": "a\u0001b\u001fc\u0000d",
    "crlf": "ok\r\nX-Injected: 1",
    "hostile_json": "\", \"admin\": true, \"x\": \"",
    "number_like": "-12.5e3",
    "leading_zero": "007",
    "emoji": "🐴 tap",
    "bad_date": "2026-02-30T10:00:00Z",
    "year_zero": "0000-01-01T00:00:00Z",
    "leap_day": "2024-02-29T12:00:00.5Z",
}
SECRETS = {"HA_TOKEN": "s3cr3t/+=", "HMAC_KEY": "whsec_test_key"}

cases = []
def case(cid, context, template, check=None):
    entry = {"id": cid, "context": context, "template": template}
    try:
        outv = ref.render(template, context, VARS, SECRETS)
        entry["output"] = outv
        if check is not None:
            assert outv == check, (cid, outv, check)
    except ref.TemplateError as e:
        entry["error"] = e.code
        if check is not None:
            assert check == ("error", e.code), (cid, e.code, check)
    cases.append(entry)

# plain and escaping
case("plain_uid", "raw", "{uid}", "04A27F1B5E8000")
case("literal_only", "raw", "no placeholders here", "no placeholders here")
case("double_brace", "raw", "{{uid}", "{uid}")
case("lone_close", "raw", "a } b", "a } b")
case("space_is_literal", "raw", "{ uid }", "{ uid }")
case("upper_after_brace_literal", "raw", "{UID}", "{UID}")
case("digit_after_brace_literal", "raw", "{1}", "{1}")
case("unterminated", "raw", "{uid", ("error", "unterminated"))
case("unterminated_nested", "raw", "{uid{seq}}", ("error", "unterminated"))
case("unknown_var", "raw", "{nope}", ("error", "unknownVariable"))
case("bad_name_char", "raw", "{uid-x}", ("error", "badName"))
case("unknown_mod", "raw", "{uid|shout}", ("error", "unknownModifier"))
case("empty_mod", "raw", "{uid|}", ("error", "unknownModifier"))
case("mod_args_on_lower", "raw", "{uid|lower:1}", ("error", "badModifierArgs"))
case("slice_no_args", "raw", "{uid|slice}", ("error", "badModifierArgs"))
case("slice_bad_arg", "raw", "{uid|slice:a}", ("error", "badModifierArgs"))
case("default_no_arg", "raw", "{uid|default}", ("error", "badModifierArgs"))
case("default_with_colons", "raw", "{counter|default:12:00}", "12:00")
case("default_empty_text", "raw", "[{counter|default:}]", "[]")
case("empty_var_renders_empty", "raw", "[{counter}]", "[]")

# modifiers
case("mod_lower", "raw", "{uid|lower}", "04a27f1b5e8000")
case("mod_upper_ascii_only", "raw", "{ndef_text|upper}", "HéLLO WöRLD ✓")
case("mod_trim", "raw", "[{crlf|slice:0:2}]", "[ok]")
case("mod_b64", "raw", "{ndef_text|b64}", "aMOpbGxvIHfDtnJsZCDinJM=")
case("mod_url", "raw", "{ndef_uri|url}", "https%3A%2F%2Ftappony.app%2Ft%2Fabc%3Fk%3D1%26x%3D2")
case("mod_colon", "raw", "{uid|colon}", "04:A2:7F:1B:5E:80:00")
case("mod_rev", "raw", "{uid|rev}", "00805E1B7FA204")
case("mod_dec", "raw", "{uid|dec}", "1304566710566912")
case("mod_dec_from_colon", "raw", "{uid_colon|dec}", "1304566710566912")
case("mod_rev_non_hex_passthrough", "raw", "{profile|rev}", "Front door")
case("mod_colon_odd_passthrough", "raw", "{uid|slice:0:3|colon}", "04A")
case("mod_unix", "raw", "{timestamp|unix}", "1790375405")
case("mod_unix_passthrough", "raw", "{profile|unix}", "Front door")
case("mod_unix_bad_date_passthrough", "raw", "{bad_date|unix}", "2026-02-30T10:00:00Z")
case("mod_unix_year_zero_passthrough", "raw", "{year_zero|unix}", "0000-01-01T00:00:00Z")
case("mod_unix_leap_day", "raw", "{leap_day|unix}", "1709208000")
case("mod_slice_codepoints", "raw", "{emoji|slice:0:1}", "🐴")
case("mod_slice_open_end", "raw", "{uid|slice:10}", "8000")
case("mod_slice_clamped", "raw", "{uid|slice:5:500}", "F1B5E8000")
case("mod_slice_reversed_empty", "raw", "[{uid|slice:5:2}]", "[]")
case("mod_default_used", "raw", "{device_label|default:phone}", "phone")
case("mod_default_unused", "raw", "{seq|default:0}", "42")
case("mod_chain", "raw", "{uid|lower|colon}", "04:A2:7F:1B:5E:80:00")
case("mod_trim_ws", "raw", "[{payload|slice:0:8|trim}]", "[Kitchen]")

# url context
case("url_context_escapes", "url", "https://example.com/t/{payload}", "https://example.com/t/Kitchen%20%22door%22%0A%09tab%5Cslash")
case("url_context_utf8", "url", "https://example.com/?q={ndef_text}", "https://example.com/?q=h%C3%A9llo%20w%C3%B6rld%20%E2%9C%93")
case("url_raw_skips", "url", "https://example.com/{ndef_uri|raw}", "https://example.com/https://tappony.app/t/abc?k=1&x=2")
case("url_url_mod_no_double", "url", "https://example.com/?u={ndef_uri|url}", "https://example.com/?u=https%3A%2F%2Ftappony.app%2Ft%2Fabc%3Fk%3D1%26x%3D2")
case("url_secret", "url", "https://example.com/?key={secret:HA_TOKEN}", "https://example.com/?key=s3cr3t%2F%2B%3D")
case("url_unknown_secret", "url", "https://example.com/?key={secret:NOPE}", ("error", "unknownSecret"))
case("url_bad_secret_name", "url", "https://example.com/?key={secret:no-pe}", ("error", "badName"))

# header context
case("header_strips_crlf", "header", "{crlf}", "okX-Injected: 1")
case("header_raw_still_strips", "header", "{crlf|raw}", "okX-Injected: 1")
case("header_strips_nul_keeps_other_controls", "header", "{control}", "a\u0001b\u001fcd")
case("header_bearer_secret", "header", "Bearer {secret:HA_TOKEN}", "Bearer s3cr3t/+=")

# form context
case("form_escapes", "form", "{payload}", "Kitchen+%22door%22%0A%09tab%5Cslash")
case("form_utf8", "form", "{ndef_text}", "h%C3%A9llo+w%C3%B6rld+%E2%9C%93")
case("form_url_mod_no_double", "form", "{ndef_uri|url}", "https%3A%2F%2Ftappony.app%2Ft%2Fabc%3Fk%3D1%26x%3D2")

# json context
case("json_in_string", "json", '{"p": "{payload}"}', '{"p": "Kitchen \\"door\\"\\n\\ttab\\\\slash"}')
case("json_controls", "json", '{"c": "{control}"}', '{"c": "a\\u0001b\\u001fc\\u0000d"}')
case("json_hostile_in_string", "json", '{"u": "{hostile_json}"}', '{"u": "\\", \\"admin\\": true, \\"x\\": \\""}')
case("json_number_outside", "json", '{"n": {seq}}', '{"n": 42}')
case("json_number_like_outside", "json", '{"n": {number_like}}', '{"n": -12.5e3}')
case("json_leading_zero_quoted", "json", '{"n": {leading_zero}}', '{"n": "007"}')
case("json_bool_outside", "json", '{"r": {random_uid}}', '{"r": false}')
case("json_empty_outside_null", "json", '{"c": {counter}}', '{"c": null}')
case("json_string_outside_quoted", "json", '{"p": {payload}}', '{"p": "Kitchen \\"door\\"\\n\\ttab\\\\slash"}')
case("json_hostile_outside_quoted", "json", '{"u": {hostile_json}}', '{"u": "\\", \\"admin\\": true, \\"x\\": \\""}')
case("json_nested_braces", "json", '{"a":{"b":{"c":"{uid}"}}}', '{"a":{"b":{"c":"04A27F1B5E8000"}}}')
case("json_escaped_quote_in_literal", "json", '{"k\\"q": "{uid}"}', '{"k\\"q": "04A27F1B5E8000"}')
case("json_array", "json", '[{seq}, "{uid}", {chip}]', '[42, "04A27F1B5E8000", "NTAG215"]')
case("json_raw_breaks_is_error", "json", '{"u": {hostile_json|raw}}', ("error", "invalidJsonBody"))
case("json_raw_valid_passes", "json", '{"n": {seq|raw}}', '{"n": 42}')
case("json_invalid_literal_is_error", "json", '{"u": "{uid}",}', ("error", "invalidJsonBody"))
case("json_trailing_content_error", "json", '{"u": 1} x', ("error", "invalidJsonBody"))
case("json_emoji_passthrough", "json", '{"e": "{emoji}"}', '{"e": "🐴 tap"}')
case("json_default_outside", "json", '{"d": {device_label|default:phone}}', '{"d": "phone"}')
case("json_unix_outside_number", "json", '{"t": {timestamp|unix}}', '{"t": 1790375405}')

# raw context
case("raw_no_escaping", "raw", "{payload}", VARS["payload"])

json.dump({"description": "Template rendering vectors. PROFILE_SCHEMA.md sections 2 to 5.",
           "variables": VARS, "secrets": SECRETS, "cases": cases},
          open(os.path.join(OUT, "template_vectors.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

# ---- host policy ---------------------------------------------------------
hcases = []
def host(url, allow, verdict, detail):
    got = ref.check_url(url, allow)
    assert got == (verdict, detail), (url, allow, got)
    hcases.append({"url": url, "allowLocalHttp": allow, "verdict": verdict, "detail": detail})

host("https://example.com/hook", False, "allowed", "publicTls")
host("https://EXAMPLE.com./hook", False, "allowed", "publicTls")
host("https://ntfy.sh/topic", False, "allowed", "publicTls")
host("https://example.com:8443/x", False, "allowed", "publicTls")
host("http://example.com/hook", True, "rejected", "plainHttpPublic")
host("http://8.8.8.8/hook", True, "rejected", "plainHttpPublic")
host("http://192.168.1.10:8123/api", True, "allowed", "localPlain")
host("http://192.168.1.10:8123/api", False, "rejected", "localHttpNotEnabled")
host("http://10.0.0.5/", True, "allowed", "localPlain")
host("http://172.16.0.1/", True, "allowed", "localPlain")
host("http://172.31.255.255/", True, "allowed", "localPlain")
host("http://172.32.0.1/", True, "rejected", "plainHttpPublic")
host("http://169.254.10.2/", True, "allowed", "localPlain")
host("http://127.0.0.1:8080/", True, "allowed", "localPlain")
host("http://homeassistant.local:8123/api/webhook/x", True, "allowed", "localPlain")
host("http://HomeAssistant.Local./x", True, "allowed", "localPlain")
host("http://nas.home.arpa/x", True, "allowed", "localPlain")
host("http://homeassistant:8123/x", True, "allowed", "localPlain")
host("https://homeassistant.local/x", False, "allowed", "localTls")
host("https://192.168.1.10/x", False, "allowed", "localTls")
host("http://[fe80::1]/x", True, "allowed", "localPlain")
host("http://[fd12:3456:789a::1]:8080/x", True, "allowed", "localPlain")
host("http://[::1]/x", True, "allowed", "localPlain")
host("http://[2001:4860:4860::8888]/x", True, "rejected", "plainHttpPublic")
host("http://[::ffff:192.168.1.1]/x", True, "allowed", "localPlain")
host("http://[::ffff:8.8.8.8]/x", True, "rejected", "plainHttpPublic")
host("https://[2001:db8::1]/x", False, "allowed", "publicTls")
host("http://3232235777/x", True, "rejected", "numericHost")
host("https://3232235777/x", False, "rejected", "numericHost")
host("http://0xC0A80101/x", True, "rejected", "numericHost")
host("http://0300.0250.1.1/x", True, "rejected", "numericHost")
host("http://192.168.1/x", True, "rejected", "numericHost")
host("http://192.168.01.1/x", True, "rejected", "numericHost")
host("http://256.1.1.1/x", True, "rejected", "numericHost")
host("http://0x7f.1/x", True, "rejected", "numericHost")
host("ftp://example.com/x", True, "rejected", "scheme")
host("javascript://example.com/x", True, "rejected", "scheme")
host("https://user:pass@example.com/x", False, "rejected", "userinfo")
host("https://@example.com/x", False, "rejected", "userinfo")
host("https:///x", False, "rejected", "malformed")
host("example.com/x", False, "rejected", "malformed")
host("https://exa mple.com/x", False, "rejected", "malformed")
host("https://-bad.com/x", False, "rejected", "malformed")
host("https://example.com:99999/x", False, "rejected", "malformed")
host("https://example.com:/x", False, "rejected", "malformed")
host("https://[2001:db8::1]:70000/x", False, "rejected", "malformed")
host("https://[2001:db8::1]:8443/x", False, "allowed", "publicTls")
host("http://[::ffff:c0a8:101]/x", True, "allowed", "localPlain")
host("http://[1:2:3:4:5:6:7:8:9]/x", True, "rejected", "malformed")
host("http://[1::2::3]/x", True, "rejected", "malformed")
host("http://[::ffff:192.168.01.1]/x", True, "rejected", "malformed")
host("http://[fc00::]/x", True, "allowed", "localPlain")
host("http://[fec0::1]/x", True, "rejected", "plainHttpPublic")
host("http://[fe80::1%25en0]/x", True, "rejected", "malformed")
host("http://[zz::1]/x", True, "rejected", "malformed")
host("https://deadbeef/x", False, "allowed", "localTls")
host("https://abc.123/x", False, "allowed", "publicTls")
host("HTTPS://Example.com/x", False, "allowed", "publicTls")
host("https://example.com?x=1", False, "allowed", "publicTls")
host("https://example.com#frag", False, "allowed", "publicTls")

tcases = []
def tmpl(t, expect):
    got = ref.check_url_template(t)
    assert got == expect, (t, got)
    tcases.append({"template": t, "result": expect})
tmpl("https://example.com/hook/{uid}", "ok")
tmpl("https://example.com/?u={uid}", "ok")
tmpl("https://{secret:HOST}/hook", "templatedAuthority")
tmpl("https://example.{tld}/hook", "templatedAuthority")
tmpl("{scheme}://example.com/", "templatedAuthority")
tmpl("https://example.com:{port}/", "templatedAuthority")
tmpl("https://example.com?q={uid}", "ok")
tmpl("no-scheme/{uid}", "malformed")

json.dump({"description": "Host policy vectors. PROFILE_SCHEMA.md section 7.", "cases": hcases, "templateCases": tcases},
          open(os.path.join(OUT, "hostpolicy_vectors.json"), "w"), indent=1)

# ---- uid -------------------------------------------------------------------
ucases = []
def uid(family, raw_hex, **expect):
    got = ref.uid_vars(family, bytes.fromhex(raw_hex))
    for k, v in expect.items():
        assert got[k] == v, (family, raw_hex, k, got[k], v)
    ucases.append({"family": family, "raw": raw_hex, "expect": got})
uid("mifare", "04A27F1B5E8000", uid="04A27F1B5E8000", uid_colon="04:A2:7F:1B:5E:80:00", uid_rev="00805E1B7FA204", uid_len="7", manufacturer="NXP", random_uid="false", uid_dec="1304566710566912")
uid("mifare", "08A1B2C3", uid="08A1B2C3", uid_len="4", random_uid="true", manufacturer="")
uid("mifare", "DE AD BE EF".replace(" ", ""), uid="DEADBEEF", random_uid="false", manufacturer="", uid_dec="3735928559")
uid("mifare", "0266A1B2C3D4E5", manufacturer="STMicroelectronics")
uid("iso15693", "E004015012345678", uid="E004015012345678", manufacturer="NXP")
uid("iso15693", "78563412500104E0", uid="E004015012345678", uid_rev="78563412500104E0", manufacturer="NXP")
uid("iso15693", "E002080011223344", manufacturer="STMicroelectronics")
uid("felica", "0114B3A2C1D0E0F0", uid="0114B3A2C1D0E0F0", manufacturer="Sony", random_uid="false")
uid("iso7816_a", "04112233445566", manufacturer="NXP")
uid("iso7816_b", "A1B2C3D4", uid="A1B2C3D4", manufacturer="", random_uid="false")
uid("mifare", "", uid="", uid_colon="", uid_dec="", uid_rev="", uid_len="0")

chips = []
def chip(kind, hexs, expect):
    fn = ref.chip_from_get_version if kind == "getVersion" else ref.chip_from_desfire_version
    got = fn(bytes.fromhex(hexs))
    assert got == expect, (kind, hexs, got)
    chips.append({"kind": kind, "response": hexs, "chip": expect})
chip("getVersion", "0004040201000F03", "NTAG213")
chip("getVersion", "0004040201001103", "NTAG215")
chip("getVersion", "0004040201001303", "NTAG216")
chip("getVersion", "0004030101000B03", "Ultralight EV1")
chip("getVersion", "0004030101000E03", "Ultralight EV1")
chip("getVersion", "0004040201001503", "")
chip("getVersion", "0005040201000F03", "")
chip("getVersion", "00040402", "")
chip("desfire", "04010101001A05", "DESFire EV1")
chip("desfire", "04010112001A05", "DESFire EV2")
chip("desfire", "04010133001A05", "DESFire EV3")
chip("desfire", "04010100001805", "DESFire")
chip("desfire", "04010177001A05", "")
chip("desfire", "0401", "")

json.dump({"description": "UID canonicalization and chip identification. PROFILE_SCHEMA.md section 8. Hardware-captured vectors from the Phase A spike are appended under 'hardware' when they exist.",
           "cases": ucases, "chips": chips, "hardware": []},
          open(os.path.join(OUT, "uid_vectors.json"), "w"), indent=1)

# ---- signing ---------------------------------------------------------------
scases = []
def sig(key, ts, body):
    scases.append({"key": key, "timestamp": ts, "body": body, "signature": ref.sign(key, ts, body)})
sig("whsec_test_key", "1790375405", '{"uid":"04A27F1B5E8000"}')
sig("whsec_test_key", "1790375405", "")
sig("k", "0", "héllo ✓")
sig("", "1790375405", "empty key")
sig("a much longer key that exceeds the sha256 block size of sixty four bytes, to test key hashing", "1790375405", "x=1&y=2")
# RFC 4231 test case 2 cross-check of the primitive (key "Jefe")
import hmac as _h, hashlib as _hl
assert _h.new(b"Jefe", b"what do ya want for nothing?", _hl.sha256).hexdigest() == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
json.dump({"description": "HMAC-SHA256 signing vectors. PROFILE_SCHEMA.md section 6. Signature covers timestamp + '.' + body.", "cases": scases},
          open(os.path.join(OUT, "signing_vectors.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

print("template", len(cases), "host", len(hcases), "tmpl", len(tcases), "uid", len(ucases), "chip", len(chips), "sig", len(scases))

# ---- variable builder --------------------------------------------------------
def text_rec(s, lang="en", utf16=False):
    body = (b"\xfe\xff" + s.encode("utf-16-be")) if utf16 else s.encode("utf-8")
    status = (0x80 if utf16 else 0) | len(lang)
    return {"tnf": 1, "type": "54", "id": "", "payload": (bytes([status]) + lang.encode() + body).hex()}
def uri_rec(code, rest):
    return {"tnf": 1, "type": "55", "id": "", "payload": (bytes([code]) + rest.encode()).hex()}

CTX = {"scanTimeMs": 1790375405123, "sendTimeMs": 1790375407000, "tz": "America/Chicago",
       "profileName": "Front door", "profileId": "4F0C2B1E-7A57-4F5B-9E0B-8C2A1D3E5F60",
       "deviceLabel": "", "platform": "ios", "nonce": "00112233445566778899aabbccddeeff", "seq": 42}
vcases = []
def vcase(cid, reading, ctx=None, **checks):
    c = dict(CTX); c.update(ctx or {})
    got = ref.build_variables(reading, c)
    for k, v in checks.items():
        assert got[k] == v, (cid, k, got[k], v)
    vcases.append({"id": cid, "reading": reading, "context": c, "expect": got})

vcase("ntag215_text", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04a27f1b5e8000", "chip": "NTAG215",
      "signature": "a1" * 32, "counter": 17, "ndef": [text_rec("Kitchen door")]},
      uid="04A27F1B5E8000", payload="Kitchen door", ndef_text="Kitchen door", ndef_uri="", counter="17", chip="NTAG215",
      timestamp="2026-09-25T22:30:05.123Z", timestamp_local="2026-09-25T17:30:05.123-05:00", unix="1790375405",
      sent_at="2026-09-25T22:30:07.000Z", seq="42", ndef_count="1", token="", manufacturer="NXP",
      ndef_json='[{"tnf":1,"type":"T","id":"","payload":"AmVuS2l0Y2hlbiBkb29y","text":"Kitchen door"}]',
      ndef_raw="0QEPVAJlbktpdGNoZW4gZG9vcg==")
vcase("launch_link", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [uri_rec(0x04, "tappony.app/t/front?k=Zx9_a-1"), text_rec("second")]},
      payload="https://tappony.app/t/front?k=Zx9_a-1", ndef_uri="https://tappony.app/t/front?k=Zx9_a-1",
      ndef_text="second", token="Zx9_a-1", ndef_count="2")
vcase("uri_other_host_no_token", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [uri_rec(0x01, "example.com/t/x?k=abc")]}, payload="http://www.example.com/t/x?k=abc", token="")
vcase("uri_unknown_prefix_code", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [uri_rec(0x40, "weird:thing")]}, payload="weird:thing")
vcase("utf16_text", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [text_rec("héllo ✓", "fr", utf16=True)]}, payload="héllo ✓", ndef_text="héllo ✓")
vcase("mime_record_base64", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [{"tnf": 2, "type": "application/json".encode().hex(), "id": "6964", "payload": b'{"a":1}'.hex()}]},
      payload="eyJhIjoxfQ==", ndef_text="", ndef_uri="",
      ndef_json='[{"tnf":2,"type":"application/json","id":"aWQ=","payload":"eyJhIjoxfQ=="}]')
vcase("absolute_uri_tnf3", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [{"tnf": 3, "type": "urn:example:thing".encode().hex(), "id": "", "payload": ""}]},
      payload="urn:example:thing", ndef_uri="urn:example:thing")
vcase("long_record_non_sr", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [text_rec("x" * 300)]}, ndef_count="1")
vcase("no_ndef", {"family": "iso15693", "tagType": "iso15693", "identifier": "78563412500104e0", "dsfid": "00", "afi": "00",
      "blockSize": 4, "blockCount": 80}, uid="E004015012345678", payload="", ndef_json="[]", ndef_raw="", ndef_count="0",
      block_size="4", block_count="80", manufacturer="NXP", counter="")
vcase("felica", {"family": "felica", "tagType": "felica", "identifier": "0114b3a2c1d0e0f0", "pmm": "0120220427674eff",
      "systemCode": "12fc"}, idm="0114B3A2C1D0E0F0", pmm="0120220427674EFF", system_code="12FC", manufacturer="Sony")
vcase("desfire_random", {"family": "mifare", "tagType": "mifare_desfire", "identifier": "08a1b2c3", "chip": "DESFire EV3",
      "historicalBytes": "8075"}, random_uid="true", historical_bytes="8075")
vcase("type_b_pupi", {"family": "iso7816_b", "tagType": "iso7816", "identifier": "a1b2c3d4", "applicationData": "00000000"},
      pupi="A1B2C3D4", application_data="00000000")
vcase("context_label_and_platform", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566"},
      {"deviceLabel": "Front desk phone", "platform": "android", "tagLabel": "Garage", "tz": "Asia/Yerevan", "seq": 0},
      device_label="Front desk phone", platform="android", tag_label="Garage", timestamp_local="2026-09-26T02:30:05.123+04:00", seq="0")
vcase("truncation", {"family": "mifare", "tagType": "mifare_ultralight", "identifier": "04112233445566",
      "ndef": [text_rec("y" * 9000)]})
assert len(vcases[-1]["expect"]["payload"]) == 8192

# ---- request builder ---------------------------------------------------------
BASE_VARS = vcases[0]["expect"]
RSECRETS = {"HA_TOKEN": "tok/en+=", "PW": "p@ss:w", "HMAC_KEY": "whsec_test_key", "API": "k-123"}
rcases = []
def rcase(cid, profile, send_unix=1790375407, check=None):
    try:
        got = ref.build_request(profile, BASE_VARS, RSECRETS, send_unix)
        entry = {"id": cid, "profile": profile, "sendUnix": send_unix, "expect": got}
    except ref.RequestError as e:
        entry = {"id": cid, "profile": profile, "sendUnix": send_unix, "error": e.code}
        got = ("error", e.code)
    if check is not None:
        assert check(got), (cid, got)
    rcases.append(entry)

def prof(**req):
    p = {"schema": 1, "id": "4F0C2B1E-7A57-4F5B-9E0B-8C2A1D3E5F60", "name": "Front door",
         "request": {"method": "POST", "url": "https://example.com/hook", "headers": [],
                     "body": {"type": "json", "template": '{"uid":"{uid}"}', "contentType": None, "fields": []},
                     "timeoutSeconds": 15, "followRedirects": False, "allowLocalHttp": False},
         "auth": {"type": "none"}, "signing": {"enabled": False, "secret": None},
         "tag": {"technologies": ["iso14443"], "extendedReads": True, "requireNdef": False},
         "after": {"messageField": None, "keepBodies": False, "sound": True, "haptic": True}}
    for k, v in req.items():
        if k in ("auth", "signing"): p[k] = v
        else: p["request"][k] = v
    return p

rcase("json_default", prof(), check=lambda g: g["body"] == '{"uid":"04A27F1B5E8000"}' and g["headers"] == [["Content-Type", "application/json"]])
rcase("ha_webhook_local", prof(url="http://homeassistant.local:8123/api/webhook/tappony-{uid|lower}", allowLocalHttp=True,
      body={"type": "json", "template": '{"uid":"{uid}","chip":"{chip}","payload":"{payload}","at":"{timestamp}","seq":{seq}}', "contentType": None, "fields": []}),
      check=lambda g: g["url"] == "http://homeassistant.local:8123/api/webhook/tappony-04a27f1b5e8000")
rcase("ha_tag_scanned_bearer", prof(url="http://192.168.1.10:8123/api/events/tag_scanned", allowLocalHttp=True,
      auth={"type": "bearer", "secret": "HA_TOKEN"}, body={"type": "json", "template": '{"tag_id":"{uid}"}', "contentType": None, "fields": []}),
      check=lambda g: g["headers"][0] == ["Authorization", "Bearer tok/en+="])
rcase("local_http_not_enabled", prof(url="http://192.168.1.10/x"), check=lambda g: g == ("error", "hostPolicy:localHttpNotEnabled"))
rcase("public_http_rejected", prof(url="http://example.com/x", allowLocalHttp=True), check=lambda g: g == ("error", "hostPolicy:plainHttpPublic"))
rcase("templated_host_rejected", prof(url="https://{payload}/x"), check=lambda g: g == ("error", "urlTemplate:templatedAuthority"))
rcase("get_query_no_body", prof(method="GET", url="https://example.com/log?uid={uid}&t={timestamp}&p={payload}"),
      check=lambda g: g["body"] is None and g["headers"] == [] and g["url"] == "https://example.com/log?uid=04A27F1B5E8000&t=2026-09-25T22%3A30%3A05.123Z&p=Kitchen%20door")
rcase("delete_ignores_body", prof(method="DELETE"), check=lambda g: g["body"] is None)
rcase("form_body", prof(body={"type": "form", "template": "", "contentType": None, "fields": [{"name": "uid", "value": "{uid}"}, {"name": "note", "value": "{payload} & more"}]}),
      check=lambda g: g["body"] == "uid=04A27F1B5E8000&note=Kitchen+door+%26+more" and g["headers"] == [["Content-Type", "application/x-www-form-urlencoded"]])
rcase("raw_body_custom_ct", prof(method="PUT", body={"type": "raw", "template": "{uid} {payload}", "contentType": "text/csv", "fields": []}),
      check=lambda g: g["body"] == "04A27F1B5E8000 Kitchen door" and g["headers"] == [["Content-Type", "text/csv"]])
rcase("user_content_type_wins", prof(headers=[{"name": "content-type", "value": "application/vnd.x+json", "secret": False}]),
      check=lambda g: g["headers"] == [["content-type", "application/vnd.x+json"]])
rcase("basic_auth", prof(auth={"type": "basic", "username": "tapper", "passwordSecret": "PW"}),
      check=lambda g: g["headers"][0] == ["Authorization", "Basic dGFwcGVyOnBAc3M6dw=="])
rcase("api_key", prof(auth={"type": "apiKey", "header": "X-API-Key", "secret": "API"}), check=lambda g: g["headers"][0] == ["X-API-Key", "k-123"])
rcase("bad_header_name", prof(headers=[{"name": "Bad Header", "value": "x", "secret": False}]), check=lambda g: g == ("error", "badHeaderName"))
rcase("header_injection_stripped", prof(headers=[{"name": "X-Note", "value": "{payload}\r\nX-Evil: 1", "secret": False}]),
      check=lambda g: g["headers"][0] == ["X-Note", "Kitchen doorX-Evil: 1"])
rcase("missing_secret", prof(auth={"type": "bearer", "secret": "NOPE"}), check=lambda g: g == ("error", "template:unknownSecret"))
rcase("signed", prof(signing={"enabled": True, "secret": "HMAC_KEY"}),
      check=lambda g: g["headers"][1:] == [["X-TapPony-Timestamp", "1790375407"], ["X-TapPony-Nonce", "00112233445566778899aabbccddeeff"],
                                           ["X-TapPony-Signature", ref.sign("whsec_test_key", "1790375407", '{"uid":"04A27F1B5E8000"}')]])
rcase("signed_get_empty_body", prof(method="GET", signing={"enabled": True, "secret": "HMAC_KEY"}),
      check=lambda g: g["headers"][-1] == ["X-TapPony-Signature", ref.sign("whsec_test_key", "1790375407", "")])
rcase("invalid_json_body", prof(body={"type": "json", "template": '{"uid":{uid|raw}}', "contentType": None, "fields": []}),
      check=lambda g: g == ("error", "template:invalidJsonBody"))
rcase("ntfy_text", prof(url="https://ntfy.sh/tappony-test", body={"type": "raw", "template": "Tag {uid} ({chip}) scanned: {payload}", "contentType": None, "fields": []}),
      check=lambda g: g["headers"] == [["Content-Type", "text/plain; charset=utf-8"]])

json.dump({"description": "Variable builder vectors (TagReading + send context -> variables).", "cases": vcases},
          open(os.path.join(OUT, "variables_vectors.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
json.dump({"description": "Request builder vectors. Variables are variables_vectors case 'ntag215_text'.",
           "variables": BASE_VARS, "secrets": RSECRETS, "cases": rcases},
          open(os.path.join(OUT, "request_vectors.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("vars", len(vcases), "requests", len(rcases))

# ---- response message ------------------------------------------------------------
BODY = json.dumps({"ok": True, "message": "Checkpoint 4 of 9", "count": 12, "ratio": 2.5,
                   "data": {"items": [{"name": "first"}, {"name": "second"}], "empty": None},
                   "nested": {"a": [1, 2], "b": "x"}, "long": "y" * 250, "unicode": "héllo ✓"},
                  ensure_ascii=False)
HEADERS = [["Content-Type", "application/json"], ["X-Result", "Logged row 17"], ["x-result", "second"]]
mcases = []
def msg(field, expect, body=BODY, headers=HEADERS):
    got = ref.extract_message(field, headers, body)
    assert got == expect, (field, got, expect)
    mcases.append({"field": field, "body": body, "headers": headers, "expect": expect})
msg(None, None)
msg("", None)
msg("json:message", "Checkpoint 4 of 9")
msg("json:count", "12")
msg("json:ratio", "2.5")
msg("json:ok", "true")
msg("json:data.items.1.name", "second")
msg("json:data.items.5.name", None)
msg("json:data.items.01.name", None)
msg("json:data.empty", None)
msg("json:nested", '{"a":[1,2],"b":"x"}')
msg("json:nested.a", "[1,2]")
msg("json:missing", None)
msg("json:long", "y" * 200)
msg("json:unicode", "héllo ✓")
msg("json:", json.dumps(json.loads(BODY), separators=(",", ":"), ensure_ascii=False)[:200])
msg("json:message", None, body="not json")
msg("json:message", None, body=None)
msg("json:0", "a", body='["a","b"]')
msg("header:X-Result", "Logged row 17")
msg("header:x-RESULT", "Logged row 17")
msg("header:X-Missing", None)
msg("bogus:thing", None)
json.dump({"description": "Response message extraction. PROFILE_SCHEMA.md section 11.", "cases": mcases},
          open(os.path.join(OUT, "message_vectors.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

# ---- history CSV -----------------------------------------------------------------
crows = [
    {"timeMs": 1790375405123, "profile": "Front door", "uid": "04A27F1B5E8000", "chip": "NTAG215", "tagType": "mifare_ultralight",
     "outcome": ref.outcome_of(None, 200), "status": 200, "latencyMs": 88, "error": ""},
    {"timeMs": 1790375406000, "profile": "Log, \"quoted\" name", "uid": "E004015012345678", "chip": "", "tagType": "iso15693",
     "outcome": ref.outcome_of(None, 503), "status": 503, "latencyMs": 1204, "error": ""},
    {"timeMs": 1790375407999, "profile": "=HYPERLINK(\"x\")", "uid": "", "chip": "", "tagType": "unknown",
     "outcome": ref.outcome_of("hostPolicy:plainHttpPublic", None), "status": None, "latencyMs": None, "error": "hostPolicy:plainHttpPublic"},
    {"timeMs": 1790375408000, "profile": " padded ", "uid": "08A1B2C3", "chip": "DESFire EV3", "tagType": "mifare_desfire",
     "outcome": ref.outcome_of(None, None), "status": None, "latencyMs": 15000, "error": "SocketTimeoutException: timeout\nline2"},
    {"timeMs": 1790375409000, "profile": "-5 degrees", "uid": "0114B3A2C1D0E0F0", "chip": "", "tagType": "felica",
     "outcome": "ok", "status": 204, "latencyMs": 40, "error": ""},
]
doc = ref.csv_document(crows)
assert doc.startswith("time,profile,uid,chip,tag_type,outcome,status,latency_ms,error\r\n")
assert "\"Log, \"\"quoted\"\" name\"" in doc and "\"'=HYPERLINK(\"\"x\"\")\"" in doc and "\" padded \"" in doc and ",'-5 degrees," in doc
assert [ref.outcome_of(None, 200), ref.outcome_of(None, 404), ref.outcome_of(None, None), ref.outcome_of("x", 200)] == ["ok", "http_error", "network_error", "not_sent"]
json.dump({"description": "History CSV export. PROFILE_SCHEMA.md section 12. RFC 4180 with CRLF, spreadsheet-formula neutralization.",
           "rows": crows, "csv": doc,
           "outcomes": [{"buildError": None, "status": 200, "outcome": "ok"}, {"buildError": None, "status": 404, "outcome": "http_error"},
                        {"buildError": None, "status": None, "outcome": "network_error"}, {"buildError": "x", "status": 200, "outcome": "not_sent"}]},
          open(os.path.join(OUT, "history_csv_vectors.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("messages", len(mcases), "csv rows", len(crows))
