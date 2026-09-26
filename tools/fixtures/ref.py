"""Reference implementation of PROFILE_SCHEMA.md sections 3 to 8.

Used only to generate and cross-check the conformance fixtures. The apps never
ship this; TapPonyKit (Swift) and :core (Kotlin) implement the same rules and
must produce identical output for every fixture.
"""
import base64, hashlib, hmac, ipaddress, json, re
from datetime import datetime, timezone

class TemplateError(Exception):
    def __init__(self, code):
        super().__init__(code); self.code = code

UNRESERVED = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
MODS0 = {"lower", "upper", "trim", "b64", "url", "colon", "rev", "dec", "unix", "raw"}
NUM_RE = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?\Z")
TS_RE = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]{1,9})?Z\Z")
NAME_RE = re.compile(r"[a-z_]+\Z")
SECRET_RE = re.compile(r"secret:([A-Za-z0-9_]+)\Z")

def pct(s):
    return "".join(chr(b) if b in UNRESERVED else "%%%02X" % b for b in s.encode("utf-8"))

def form(s):
    out = []
    for b in s.encode("utf-8"):
        if b in UNRESERVED: out.append(chr(b))
        elif b == 0x20: out.append("+")
        else: out.append("%%%02X" % b)
    return "".join(out)

def json_escape(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '"': out.append('\\"')
        elif ch == "\\": out.append("\\\\")
        elif ch == "\b": out.append("\\b")
        elif ch == "\f": out.append("\\f")
        elif ch == "\n": out.append("\\n")
        elif ch == "\r": out.append("\\r")
        elif ch == "\t": out.append("\\t")
        elif o < 0x20: out.append("\\u%04x" % o)
        else: out.append(ch)
    return "".join(out)

def hex_bytes(s):
    t = re.sub(r"[:\- ]", "", s)
    if len(t) == 0 or len(t) % 2 or not re.fullmatch(r"[0-9A-Fa-f]+", t):
        return None
    return bytes.fromhex(t)

def ascii_lower(s): return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)
def ascii_upper(s): return "".join(chr(ord(c) - 32) if "a" <= c <= "z" else c for c in s)

def apply_mod(v, name, args):
    if name == "lower": return ascii_lower(v)
    if name == "upper": return ascii_upper(v)
    if name == "trim": return v.strip(" \t\r\n")
    if name == "b64": return base64.b64encode(v.encode("utf-8")).decode()
    if name == "url": return pct(v)
    if name in ("colon", "rev", "dec"):
        b = hex_bytes(v)
        if b is None: return v
        if name == "colon": return ":".join("%02X" % x for x in b)
        if name == "rev": return b[::-1].hex().upper()
        return str(int.from_bytes(b, "big"))
    if name == "unix":
        m = TS_RE.match(v)
        if not m: return v
        y, mo, d, h, mi, s = (int(m.group(i)) for i in range(1, 7))
        try:
            dt = datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc)
        except ValueError:
            return v
        return str(int(dt.timestamp()))
    if name == "slice":
        cps = list(v)
        a = int(args[0]); b = int(args[1]) if len(args) > 1 else len(cps)
        a = max(0, min(a, len(cps))); b = max(a, min(b, len(cps)))
        return "".join(cps[a:b])
    if name == "default": return args[0] if v == "" else v
    if name == "raw": return v
    raise TemplateError("unknownModifier")

def parse_placeholder(body):
    if body == "": raise TemplateError("emptyPlaceholder")
    parts = body.split("|")
    head, mods = parts[0], parts[1:]
    sm = SECRET_RE.match(head)
    if sm: var = ("secret", sm.group(1))
    elif NAME_RE.match(head): var = ("var", head)
    else: raise TemplateError("badName")
    parsed = []
    for m in mods:
        name, colon, rest = m.partition(":")
        if name == "default":
            if not colon: raise TemplateError("badModifierArgs")
            parsed.append((name, [rest])); continue
        args = rest.split(":") if colon else []
        if name in MODS0:
            if args: raise TemplateError("badModifierArgs")
        elif name == "slice":
            if len(args) not in (1, 2) or not all(re.fullmatch(r"[0-9]+", a) for a in args):
                raise TemplateError("badModifierArgs")
        else:
            raise TemplateError("unknownModifier")
        parsed.append((name, args))
    return var, parsed

def tokenize(t):
    """Return list of ('lit', text) / ('ph', body).

    A '{' starts a placeholder only when the next character is a-z or '_'
    (a variable name, or 'secret:'). Every other '{' is literal, which is what
    lets a JSON template be written as plain JSON. '{{' is a literal '{' for the
    rare case where literal text must be followed by a lowercase letter.
    '}' is always literal outside a placeholder.
    """
    out, i, buf = [], 0, []
    n = len(t)
    while i < n:
        c = t[i]
        if c == "{":
            if i + 1 < n and t[i + 1] == "{":
                buf.append("{"); i += 2; continue
            if i + 1 < n and ("a" <= t[i + 1] <= "z" or t[i + 1] == "_"):
                j = i + 1
                while j < n and t[j] not in "{}":
                    j += 1
                if j >= n or t[j] != "}": raise TemplateError("unterminated")
                if buf: out.append(("lit", "".join(buf))); buf = []
                out.append(("ph", t[i + 1:j])); i = j + 1; continue
        buf.append(c); i += 1
    if buf: out.append(("lit", "".join(buf)))
    return out

def json_in_string_flags(tokens):
    """For a JSON template, mark each placeholder as inside a string literal or not,
    by scanning the literal text with a string/escape state machine."""
    flags, in_str, esc = [], False, False
    for kind, text in tokens:
        if kind == "ph": flags.append(in_str); continue
        for ch in text:
            if in_str:
                if esc: esc = False
                elif ch == "\\": esc = True
                elif ch == '"': in_str = False
            elif ch == '"': in_str = True
    return flags

def value_of(var, variables, secrets):
    kind, name = var
    if kind == "secret":
        if name not in secrets: raise TemplateError("unknownSecret")
        return secrets[name]
    if name not in variables: raise TemplateError("unknownVariable")
    return variables[name]

def render(template, context, variables, secrets=None):
    secrets = secrets or {}
    tokens = tokenize(template)
    phs = [(parse_placeholder(b) if k == "ph" else None) for k, b in tokens]
    flags = json_in_string_flags(tokens) if context == "json" else None
    out, pi = [], 0
    for (kind, text), ph in zip(tokens, phs):
        if kind == "lit":
            out.append(form(text) if context == "form" else text); continue
        var, mods = ph
        v = value_of(var, variables, secrets)
        for name, args in mods: v = apply_mod(v, name, args)
        skip = any(n in ("url", "raw") for n, _ in mods)
        if context == "header":
            v = v.replace("\r", "").replace("\n", "").replace("\x00", "")
        elif context == "raw" or skip:
            pass
        elif context == "url": v = pct(v)
        elif context == "form": v = form(v)
        elif context == "json":
            if flags[pi]: v = json_escape(v)
            elif v == "": v = "null"
            elif NUM_RE.match(v) or v in ("true", "false", "null"): pass
            else: v = '"' + json_escape(v) + '"'
        else:
            raise ValueError(context)
        pi += 1
        out.append(v)
    s = "".join(out)
    if context == "json":
        if not valid_json(s): raise TemplateError("invalidJsonBody")
    return s

def valid_json(s):
    # RFC 8259 strict: Python's json is lenient about NaN/Infinity; reject those.
    try:
        json.loads(s, parse_constant=lambda c: (_ for _ in ()).throw(ValueError(c)))
        return True
    except Exception:
        return False

# ---- host policy -------------------------------------------------------

def _strict_v4(h):
    parts = h.split(".")
    if len(parts) != 4: return None
    for p in parts:
        if not re.fullmatch(r"(0|[1-9][0-9]{0,2})", p) or int(p) > 255: return None
    return ipaddress.IPv4Address(h)

LOCAL4 = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "127.0.0.0/8")]
LOCAL6 = [ipaddress.ip_network(n) for n in ("::1/128", "fe80::/10", "fc00::/7")]
HOST_RE = re.compile(r"[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\Z")

def check_url(url, allow_local_http):
    """Returns (verdict, detail). verdict in: allowed, rejected. detail is the class or reason."""
    m = re.match(r"([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)(.*)\Z", url, re.S)
    if not m: return ("rejected", "malformed")
    scheme, authority = m.group(1).lower(), m.group(2)
    if scheme not in ("http", "https"): return ("rejected", "scheme")
    if "@" in authority: return ("rejected", "userinfo")
    if authority.startswith("["):
        k = authority.find("]")
        if k < 0: return ("rejected", "malformed")
        host, rest = authority[1:k], authority[k + 1:]
        if rest and (not re.fullmatch(r":[0-9]{1,5}", rest) or int(rest[1:]) > 65535): return ("rejected", "malformed")
        try:
            ip6 = ipaddress.IPv6Address(host)
        except ValueError:
            return ("rejected", "malformed")
        if "%" in host: return ("rejected", "malformed")
        mapped = ip6.ipv4_mapped
        local = any(mapped in n for n in LOCAL4) if mapped else any(ip6 in n for n in LOCAL6)
    else:
        host, _, port = authority.partition(":")
        if ":" in authority and not re.fullmatch(r"[0-9]{1,5}", port): return ("rejected", "malformed")
        if port and int(port) > 65535: return ("rejected", "malformed")
        host = host.lower()
        if host.endswith("."): host = host[:-1]
        if host == "": return ("rejected", "malformed")
        v4 = _strict_v4(host)
        if v4 is not None:
            local = any(v4 in n for n in LOCAL4)
        else:
            if re.fullmatch(r"[0-9a-fx.]+", host) and (re.fullmatch(r"[0-9.]+", host) or any(p.startswith("0x") for p in host.split("."))):
                return ("rejected", "numericHost")
            if not HOST_RE.match(host): return ("rejected", "malformed")
            local = host.endswith(".local") or host.endswith(".home.arpa") or "." not in host
    if scheme == "https":
        return ("allowed", "localTls" if local else "publicTls")
    if not local: return ("rejected", "plainHttpPublic")
    if not allow_local_http: return ("rejected", "localHttpNotEnabled")
    return ("allowed", "localPlain")

def check_url_template(template):
    """Save-time rule: scheme and authority must be literal."""
    head = template.split("://", 1)
    if len(head) != 2: return "malformed"
    authority = head[1].split("/", 1)[0].split("?", 1)[0].split("#", 1)[0]
    if "{" in head[0] or "{" in authority: return "templatedAuthority"
    return "ok"

# ---- uid ----------------------------------------------------------------

MFR = {0x01: "Motorola", 0x02: "STMicroelectronics", 0x03: "Hitachi", 0x04: "NXP", 0x05: "Infineon",
       0x06: "Cylink", 0x07: "Texas Instruments", 0x08: "Fujitsu", 0x09: "Matsushita", 0x0A: "NEC",
       0x0B: "Oki", 0x0C: "Toshiba", 0x0D: "Mitsubishi", 0x0E: "Samsung", 0x0F: "Hynix", 0x10: "LG",
       0x11: "Emosyn-EM", 0x12: "INSIDE Technology", 0x13: "ORGA", 0x14: "Sharp", 0x15: "Atmel",
       0x16: "EM Microelectronic"}

def canonical(family, raw):
    b = bytes(raw)
    if family == "iso15693" and len(b) > 1 and b[0] != 0xE0 and b[-1] == 0xE0:
        b = b[::-1]
    return b

def uid_vars(family, raw):
    b = canonical(family, raw)
    hx = b.hex().upper()
    if family == "felica": mfr = "Sony"
    elif family == "iso15693" and len(b) >= 2 and b[0] == 0xE0: mfr = MFR.get(b[1], "")
    elif family in ("mifare", "iso7816_a") and len(b) == 7: mfr = MFR.get(b[0], "")
    else: mfr = ""
    return {
        "uid": hx,
        "uid_colon": ":".join("%02X" % x for x in b),
        "uid_dec": str(int.from_bytes(b, "big")) if b else "",
        "uid_rev": b[::-1].hex().upper(),
        "uid_len": str(len(b)),
        "random_uid": "true" if family in ("mifare", "iso7816_a") and len(b) == 4 and b[0] == 0x08 else "false",
        "manufacturer": mfr,
    }

def chip_from_get_version(resp):
    b = bytes(resp)
    if len(b) != 8 or b[1] != 0x04: return ""
    ptype, sub, size = b[2], b[3], b[6]
    if ptype == 0x04 and sub == 0x02:
        return {0x0F: "NTAG213", 0x11: "NTAG215", 0x13: "NTAG216"}.get(size, "")
    if ptype == 0x03 and sub == 0x01:
        return {0x0B: "Ultralight EV1", 0x0E: "Ultralight EV1"}.get(size, "")
    return ""

def chip_from_desfire_version(hw):
    b = bytes(hw)
    if len(b) < 4 or b[0] != 0x04 or b[1] != 0x01: return ""
    return {0x00: "DESFire", 0x01: "DESFire EV1", 0x12: "DESFire EV2", 0x33: "DESFire EV3"}.get(b[3], "")

# ---- signing --------------------------------------------------------------

def sign(key, timestamp, body):
    return "sha256=" + hmac.new(key.encode("utf-8"), (timestamp + "." + body).encode("utf-8"), hashlib.sha256).hexdigest()

# ---- NDEF ------------------------------------------------------------------

URI_PREFIXES = ["", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:",
    "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://", "sftp://", "smb://", "nfs://", "ftp://",
    "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:", "tftp:",
    "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
    "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:"]

CAP = 8192

def cap(s):
    return s if len(s) <= CAP else s[:CAP]

def ndef_encode(records):
    """records: list of dict(tnf=int, type=bytes, id=bytes, payload=bytes). NFC Forum NDEF 1.0."""
    out = bytearray()
    for i, r in enumerate(records):
        sr = len(r["payload"]) < 256
        il = len(r["id"]) > 0
        h = (r["tnf"] & 0x07)
        if i == 0: h |= 0x80
        if i == len(records) - 1: h |= 0x40
        if sr: h |= 0x10
        if il: h |= 0x08
        out.append(h)
        out.append(len(r["type"]))
        if sr: out.append(len(r["payload"]))
        else: out += len(r["payload"]).to_bytes(4, "big")
        if il: out.append(len(r["id"]))
        out += r["type"]; out += r["id"]; out += r["payload"]
    return bytes(out)

def text_of(r):
    if r["tnf"] != 1 or r["type"] != b"T" or len(r["payload"]) < 1: return None
    p = r["payload"]; status = p[0]; ll = status & 0x3F
    body = p[1 + ll:]
    if status & 0x80:
        if body[:2] == b"\xff\xfe": return body[2:].decode("utf-16-le", "replace")
        if body[:2] == b"\xfe\xff": return body[2:].decode("utf-16-be", "replace")
        return body.decode("utf-16-be", "replace")
    return body.decode("utf-8", "replace")

def uri_of(r):
    if r["tnf"] == 1 and r["type"] == b"U" and len(r["payload"]) >= 1:
        code = r["payload"][0]
        pre = URI_PREFIXES[code] if code < len(URI_PREFIXES) else ""
        return pre + r["payload"][1:].decode("utf-8", "replace")
    if r["tnf"] == 3:
        return r["type"].decode("utf-8", "replace")
    return None

def b64(b): return base64.b64encode(b).decode()

def ndef_vars(records):
    if not records:
        return {"payload": "", "ndef_text": "", "ndef_uri": "", "ndef_json": "[]", "ndef_raw": "", "ndef_count": "0"}
    first = records[0]
    t, u = text_of(first), uri_of(first)
    payload = t if t is not None else (u if u is not None else b64(first["payload"]))
    ndef_text = next((x for x in (text_of(r) for r in records) if x is not None), "")
    ndef_uri = next((x for x in (uri_of(r) for r in records) if x is not None), "")
    parts = []
    for r in records:
        fields = ['"tnf":%d' % r["tnf"], '"type":"%s"' % json_escape(r["type"].decode("latin-1")),
                  '"id":"%s"' % b64(r["id"]), '"payload":"%s"' % b64(r["payload"])]
        tx, ux = text_of(r), uri_of(r)
        if tx is not None: fields.append('"text":"%s"' % json_escape(tx))
        if ux is not None: fields.append('"uri":"%s"' % json_escape(ux))
        parts.append("{" + ",".join(fields) + "}")
    return {"payload": cap(payload), "ndef_text": cap(ndef_text), "ndef_uri": cap(ndef_uri),
            "ndef_json": cap("[" + ",".join(parts) + "]"), "ndef_raw": cap(b64(ndef_encode(records))),
            "ndef_count": str(len(records))}

# ---- variable builder --------------------------------------------------------

from datetime import timedelta
from zoneinfo import ZoneInfo

def iso_utc(ms):
    dt = datetime.fromtimestamp(ms // 1000, tz=timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + ".%03dZ" % (ms % 1000)

def iso_local(ms, tz):
    dt = datetime.fromtimestamp(ms // 1000, tz=ZoneInfo(tz))
    off = dt.utcoffset(); mins = int(off.total_seconds() // 60)
    sign = "+" if mins >= 0 else "-"; mins = abs(mins)
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + ".%03d%s%02d:%02d" % (ms % 1000, sign, mins // 60, mins % 60)

def token_of(uri):
    m = re.match(r"https://tappony\.app/t/[^?#]*\?(?:[^#]*&)?k=([A-Za-z0-9_-]+)", uri)
    return m.group(1) if m else ""

def hx(s): return (s or "").upper()

def build_variables(reading, ctx):
    fam = reading["family"]
    raw = bytes.fromhex(reading.get("identifier", ""))
    v = uid_vars(fam, raw)
    recs = [{"tnf": r["tnf"], "type": bytes.fromhex(r["type"]), "id": bytes.fromhex(r.get("id", "")),
             "payload": bytes.fromhex(r["payload"])} for r in reading.get("ndef", [])]
    nv = ndef_vars(recs)
    out = dict(v)
    out.update({
        "tag_type": reading.get("tagType", "unknown"),
        "chip": reading.get("chip", ""),
        "signature": hx(reading.get("signature")),
        "counter": "" if reading.get("counter") is None else str(reading["counter"]),
        "atqa": hx(reading.get("atqa")), "sak": hx(reading.get("sak")),
        "dsfid": hx(reading.get("dsfid")), "afi": hx(reading.get("afi")),
        "block_size": "" if reading.get("blockSize") is None else str(reading["blockSize"]),
        "block_count": "" if reading.get("blockCount") is None else str(reading["blockCount"]),
        "idm": v["uid"] if fam == "felica" else "",
        "pmm": hx(reading.get("pmm")), "system_code": hx(reading.get("systemCode")),
        "pupi": v["uid"] if fam == "iso7816_b" else "",
        "historical_bytes": hx(reading.get("historicalBytes")),
        "application_data": hx(reading.get("applicationData")),
        "tag_label": ctx.get("tagLabel", ""),
    })
    out.update(nv)
    out["token"] = token_of(nv["ndef_uri"])
    ms, sent = ctx["scanTimeMs"], ctx["sendTimeMs"]
    out.update({
        "timestamp": iso_utc(ms), "timestamp_local": iso_local(ms, ctx["tz"]), "unix": str(ms // 1000),
        "tz": ctx["tz"], "sent_at": iso_utc(sent), "profile": ctx["profileName"], "profile_id": ctx["profileId"],
        "device_label": ctx.get("deviceLabel", ""), "platform": ctx["platform"], "nonce": ctx["nonce"],
        "seq": str(ctx["seq"]),
    })
    return out

# ---- request builder ---------------------------------------------------------

TOKEN_RE = re.compile(r"[!#$%&'*+\-.^_`|~0-9A-Za-z]+\Z")
DEFAULT_CT = {"json": "application/json", "form": "application/x-www-form-urlencoded", "raw": "text/plain; charset=utf-8"}

class RequestError(Exception):
    def __init__(self, code):
        super().__init__(code); self.code = code

def build_request(profile, variables, secrets, send_unix):
    req = profile["request"]
    method = req["method"]
    if method not in ("GET", "POST", "PUT", "PATCH", "DELETE"): raise RequestError("badMethod")
    if check_url_template(req["url"]) != "ok": raise RequestError("urlTemplate:" + check_url_template(req["url"]))
    try:
        url = render(req["url"], "url", variables, secrets)
    except TemplateError as e:
        raise RequestError("template:" + e.code)
    verdict, detail = check_url(url, req.get("allowLocalHttp", False))
    if verdict != "allowed": raise RequestError("hostPolicy:" + detail)
    headers = []
    def add(n, vtpl):
        if not TOKEN_RE.match(n): raise RequestError("badHeaderName")
        try:
            headers.append([n, render(vtpl, "header", variables, secrets)])
        except TemplateError as e:
            raise RequestError("template:" + e.code)
    for h in req.get("headers", []):
        add(h["name"], h["value"])
    auth = profile.get("auth") or {"type": "none"}
    at = auth.get("type", "none")
    def sec(name):
        if name not in secrets: raise RequestError("template:unknownSecret")
        return secrets[name]
    if at == "bearer": headers.append(["Authorization", "Bearer " + sec(auth["secret"])])
    elif at == "basic":
        headers.append(["Authorization", "Basic " + b64((auth["username"] + ":" + sec(auth["passwordSecret"])).encode("utf-8"))])
    elif at == "apiKey":
        if not TOKEN_RE.match(auth["header"]): raise RequestError("badHeaderName")
        headers.append([auth["header"], sec(auth["secret"])])
    elif at != "none": raise RequestError("badAuth")
    for h in headers: h[1] = h[1].replace("\r", "").replace("\n", "").replace("\x00", "")
    body_spec = req.get("body") or {"type": "none"}
    bt = body_spec.get("type", "none")
    body = None
    if method not in ("GET", "DELETE") and bt != "none":
        try:
            if bt == "json": body = render(body_spec.get("template", ""), "json", variables, secrets)
            elif bt == "raw": body = render(body_spec.get("template", ""), "raw", variables, secrets)
            elif bt == "form":
                body = "&".join(render(f["name"], "form", variables, secrets) + "=" + render(f["value"], "form", variables, secrets)
                                for f in body_spec.get("fields", []))
            else: raise RequestError("badBodyType")
        except TemplateError as e:
            raise RequestError("template:" + e.code)
        if not any(h[0].lower() == "content-type" for h in headers):
            headers.append(["Content-Type", body_spec.get("contentType") or DEFAULT_CT[bt]])
    sg = profile.get("signing") or {"enabled": False}
    if sg.get("enabled"):
        key = sec(sg["secret"])
        ts = str(send_unix)
        headers.append(["X-TapPony-Timestamp", ts])
        headers.append(["X-TapPony-Nonce", variables["nonce"]])
        headers.append(["X-TapPony-Signature", sign(key, ts, body or "")])
    return {"method": method, "url": url, "headers": headers, "body": body}

# ---- response message ----------------------------------------------------------

MESSAGE_CAP = 200

def compact(v):
    return json.dumps(v, separators=(",", ":"), ensure_ascii=False)

def extract_message(field, headers, body):
    """PROFILE_SCHEMA.md section 11. headers: list of [name, value]. Returns str or None."""
    if not field:
        return None
    if field.startswith("header:"):
        name = field[len("header:"):].lower()
        for n, v in headers:
            if n.lower() == name:
                return v[:MESSAGE_CAP]
        return None
    if field.startswith("json:"):
        path = field[len("json:"):]
        if body is None or not valid_json(body):
            return None
        cur = json.loads(body)
        if path:
            for seg in path.split("."):
                if isinstance(cur, dict) and seg in cur:
                    cur = cur[seg]
                elif isinstance(cur, list) and re.fullmatch(r"(0|[1-9][0-9]*)", seg) and int(seg) < len(cur):
                    cur = cur[int(seg)]
                else:
                    return None
        if cur is None:
            return None
        if isinstance(cur, str):
            out = cur
        elif isinstance(cur, bool):
            out = "true" if cur else "false"
        elif isinstance(cur, int):
            out = str(cur)
        elif isinstance(cur, float):
            out = str(int(cur)) if cur == int(cur) and abs(cur) < 1e15 else repr(cur)
        else:
            out = compact(cur)
        return out[:MESSAGE_CAP]
    return None

# ---- history CSV -----------------------------------------------------------------

CSV_HEADER = ["time", "profile", "uid", "chip", "tag_type", "outcome", "status", "latency_ms", "error"]

def outcome_of(build_error, status):
    if build_error: return "not_sent"
    if status is None: return "network_error"
    return "ok" if 200 <= status <= 299 else "http_error"

def csv_field(s):
    if s and s[0] in "=+-@\t\r":
        s = "'" + s
    if any(c in s for c in ',"\r\n') or (s != s.strip(" ")):
        s = '"' + s.replace('"', '""') + '"'
    return s

def csv_row(r):
    vals = [iso_utc(r["timeMs"]), r["profile"], r["uid"], r["chip"], r["tagType"], r["outcome"],
            "" if r.get("status") is None else str(r["status"]),
            "" if r.get("latencyMs") is None else str(r["latencyMs"]), r.get("error") or ""]
    return ",".join(csv_field(v) for v in vals)

def csv_document(rows):
    return "\r\n".join([",".join(CSV_HEADER)] + [csv_row(r) for r in rows]) + "\r\n"

# ---- rules -----------------------------------------------------------------------

RULE_FIELDS = ["uid", "tag_type", "chip", "manufacturer", "payload", "ndef_text", "ndef_uri"]
RULE_OPS = ["equals", "prefix", "contains", "regex"]

def _norm_uid(s):
    return ascii_upper(re.sub(r"[:\- ]", "", s))

def rule_error(rule):
    """None when valid, else a code: unknownField, unknownOp, badRegex, noProfiles."""
    m = rule.get("match", {})
    if m.get("field") not in RULE_FIELDS: return "unknownField"
    if m.get("op") not in RULE_OPS: return "unknownOp"
    if m.get("op") == "regex":
        try: re.compile(m.get("value", ""))
        except re.error: return "badRegex"
    if not rule.get("profiles"): return "noProfiles"
    return None

def rule_matches(rule, variables):
    if not rule.get("enabled", True) or rule_error(rule) is not None:
        return False
    m = rule["match"]
    field, op, want = m["field"], m["op"], m.get("value", "")
    have = variables.get(field, "")
    if op == "regex":
        return re.search(want, have) is not None
    if field == "uid":
        have, want = _norm_uid(have), _norm_uid(want)
    else:
        have, want = ascii_lower(have), ascii_lower(want)
    if op == "equals": return have == want
    if op == "prefix": return have.startswith(want)
    return want in have

def route(ruleset, variables, active_id):
    """Returns (profile_ids, rule_id). rule_id None means no rule decided."""
    fallback = [active_id] if active_id else []
    if not ruleset.get("enabled", False):
        return (fallback, None)
    for r in ruleset.get("rules", []):
        if rule_matches(r, variables):
            seen, ids = set(), []
            for p in r["profiles"]:
                if p not in seen:
                    seen.add(p); ids.append(p)
            return (ids, r["id"])
    if ruleset.get("unmatched", "active") == "ignore":
        return ([], None)
    return (fallback, None)

# ---- result text -----------------------------------------------------------------

def result_text(template, status, message, uid, profile):
    """Custom success or failure text. None template -> None. Broken template -> shown as typed."""
    if template is None or template == "":
        return None
    vars_ = {"status": "" if status is None else str(status), "message": message or "", "uid": uid, "profile": profile}
    try:
        out = render(template, "raw", vars_, {})
    except TemplateError:
        out = template
    return out[:MESSAGE_CAP]
