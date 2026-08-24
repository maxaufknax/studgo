#!/usr/bin/env python3
"""StudGo Dev-CLI — OAuth2-Flow gegen Stud.IP LUH testen und die JSON:API erkunden.

  ./tools/studip-cli.py login            # PKCE-Flow über den Browser
  ./tools/studip-cli.py login --cookie   # ohne Browser, via Sitzungscookie
  ./tools/studip-cli.py refresh          # Access-Token erneuern
  ./tools/studip-cli.py get /v1/users/me # authentifizierter API-Call
  ./tools/studip-cli.py whoami
"""
import base64, hashlib, json, re, secrets, sys, urllib.parse, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKEN_FILE = ROOT / "tools" / ".token.json"


def load_env():
    env = {}
    for line in (ROOT / ".env").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


ENV = load_env()
BASE = ENV["STUDIP_BASE_URL"]
AUTHORIZE = f"{BASE}/dispatch.php/api/oauth2/authorize"
TOKEN = f"{BASE}/dispatch.php/api/oauth2/token"
API = f"{BASE}/jsonapi.php"



def studip_error(raw):
    """Stud.IP liefert OAuth-Fehler als HTML-Seite; die Meldung steht in
    <div class="messagebox_details"><ul><li>...</li></ul></div>."""
    import html as htmlmod
    import re
    block = re.search(r'messagebox_details.*?>(.*?)</div>', raw, re.S)
    if not block:
        return " ".join(raw.split())[:300]
    items = re.findall(r"<li>(.*?)</li>", block.group(1), re.S)
    text = " | ".join(items) if items else block.group(1)
    return " ".join(htmlmod.unescape(re.sub(r"<[^>]+>", " ", text)).split())


def post_form(url, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        sys.exit(f"HTTP {e.code}: {studip_error(raw)}")


def save_token(tok):
    TOKEN_FILE.write_text(json.dumps(tok, indent=2))
    TOKEN_FILE.chmod(0o600)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Weiterleitungen nicht folgen — der Location-Header ist das Ziel."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http(url, cookie, data=None):
    """Ein Request mit Stud.IP-Sitzungscookie, ohne Weiterleitung zu folgen.

    Gibt (status, headers, body) zurück; ein 302 ist hier Erfolg, kein Fehler.
    """
    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url, data=data)
    req.add_header("Cookie", cookie)
    req.add_header("User-Agent", "StudGo-DevCLI")
    if data:
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with opener.open(req, timeout=30) as r:
            return r.status, r.headers, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode("utf-8", "replace")


def approve_form(html):
    """Aus der Zustimmungsseite die versteckten Felder des Erlauben-Formulars.

    Die Seite trägt zwei Formulare auf denselben Endpunkt; das Ablehnen-
    Formular erkennt man am Feld `_method` mit dem Wert delete.
    """
    fields = None
    for form in re.findall(r"<form\b.*?</form>", html, re.S | re.I):
        hidden = dict(re.findall(
            r'<input[^>]+type="hidden"[^>]+name="([^"]+)"[^>]+value="([^"]*)"', form))
        if "auth_token" not in hidden:
            continue
        if hidden.get("_method", "").lower() == "delete":
            continue
        fields = hidden
    return fields


def code_via_cookie(authorize_url, cookie):
    """Holt den Autorisierungscode ohne Browser: Zustimmungsseite abrufen,
    Formular absenden, Code aus dem Location-Header lesen."""
    status, headers, body = http(authorize_url, cookie)

    if status in (301, 302, 303, 307, 308):
        location = headers.get("Location", "")
        # Ohne gültige Sitzung schickt Stud.IP zur Anmeldemaske statt zum Client.
        if "/dispatch.php/login" in location:
            raise SystemExit(
                "Stud.IP leitet zur Anmeldung um — der Cookie gehört zu keiner "
                "angemeldeten Sitzung.\n"
                "  Bist du im Browser wirklich eingeloggt? Und hast du den "
                "kompletten Wert der cookie-Zeile kopiert, nicht nur einen Teil?")
        return location

    if status != 200:
        raise SystemExit(f"Authorize antwortete mit HTTP {status}: {studip_error(body)}")

    if "Autorisierungsanfrage" not in body and "auth_token" not in body:
        raise SystemExit(
            "Stud.IP hat keine Zustimmungsseite geliefert — vermutlich ist der "
            "Cookie abgelaufen oder gehört zu keiner angemeldeten Sitzung.")

    fields = approve_form(body)
    if not fields:
        raise SystemExit("Das Erlauben-Formular war in der Antwort nicht auffindbar.")

    fields["allow"] = "1"
    status, headers, body = http(authorize_url, cookie,
                                 data=urllib.parse.urlencode(fields).encode())

    location = headers.get("Location")
    if not location:
        raise SystemExit(f"Kein Location-Header nach dem Absenden (HTTP {status}): "
                         f"{studip_error(body)}")
    return location


def extract_code(pasted, state):
    """Nimmt Redirect-URL, Query-Fragment oder blanken Code entgegen.

    Der häufigste Fehlgriff ist, die *Authorize*-URL zurückzukopieren statt
    der Adresse, auf der Stud.IP danach landet — das wird hier abgefangen,
    statt sie als Code an den Server zu schicken.
    """
    pasted = pasted.strip().strip('"\'')
    if not pasted:
        return None, "Nichts eingegeben."

    if "/oauth2/authorize" in pasted or "code_challenge" in pasted:
        return None, ("Das ist die Authorize-URL von Schritt 1, nicht die "
                      "Rückleitung. Gebraucht wird die Adresse, die nach "
                      "'Zugriff erlauben' im Browser steht — sie beginnt mit "
                      "studgo://oauth/callback?code=")

    looks_like_url = "://" in pasted
    if not (looks_like_url or "=" in pasted):
        return pasted, None  # blanker Code

    # Fragment abschneiden, manche Browser hängen ein '#/' an
    head = pasted.split("#", 1)[0]
    query = urllib.parse.urlparse(head).query if looks_like_url else head.split("?", 1)[-1]
    params = urllib.parse.parse_qs(query)

    # Eine Ablehnung kommt ohne code, aber mit Begründung — die gehört gezeigt.
    if "error" in params:
        detail = params.get("error_description", [""])[0]
        return None, f"Stud.IP hat abgelehnt: {params['error'][0]} {detail}".strip()

    if "code" not in params:
        return None, "In dieser Adresse steckt kein code-Parameter."

    if params.get("state", [state])[0] != state:
        return None, "Der state stimmt nicht überein — bitte den Flow neu starten."

    return params["code"][0], None


def cmd_login(use_cookie=False):
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    params = {
        "response_type": "code",
        "client_id": ENV["STUDIP_CLIENT_ID"],
        "redirect_uri": ENV["STUDIP_REDIRECT_URI"],
        "scope": ENV.get("STUDIP_SCOPE", "api"),
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    authorize_url = f"{AUTHORIZE}?{urllib.parse.urlencode(params)}"

    code = (login_with_cookie(authorize_url, state) if use_cookie
            else login_with_browser(authorize_url, state))

    tok = post_form(TOKEN, {
        "grant_type": "authorization_code",
        "client_id": ENV["STUDIP_CLIENT_ID"],
        "client_secret": ENV["STUDIP_CLIENT_SECRET"],
        "redirect_uri": ENV["STUDIP_REDIRECT_URI"],
        "code": code,
        "code_verifier": verifier,
    })
    save_token(tok)
    print(f"\nOK — Token gespeichert in {TOKEN_FILE}")
    print(f"   gültig für {tok.get('expires_in')}s, "
          f"refresh_token: {'ja' if tok.get('refresh_token') else 'nein'}")
    print("\n   Weiter mit:  ./tools/studip-cli.py whoami")


def login_with_cookie(authorize_url, state):
    """Ohne Browser: mit der bestehenden Stud.IP-Sitzung zustimmen.

    Nötig, weil Browser die Weiterleitung auf studgo:// kommentarlos
    verwerfen — der Code ist dann zwar erzeugt, aber nirgends ablesbar.
    """
    print("""
So kommst du an den Cookie:

  1. studip.uni-hannover.de im Browser öffnen und normal anmelden
  2. F12 → Reiter "Netzwerk", dann die Seite neu laden
  3. Irgendeinen Eintrag anklicken → "Kopfzeilen" / "Headers"
  4. Unter den Anfrage-Headern die Zeile  cookie:  suchen
     und ihren kompletten Wert kopieren

Der Cookie ist nur für diese Sitzung gültig und wird nirgends gespeichert.
""")
    cookie = input("Cookie-Wert einfügen: ").strip()
    if not cookie:
        sys.exit("Kein Cookie angegeben.")
    if cookie.lower().startswith("cookie:"):
        cookie = cookie.split(":", 1)[1].strip()

    print("\nZustimmung wird abgeholt…")
    location = code_via_cookie(authorize_url, cookie)
    code, problem = extract_code(location, state)
    if not code:
        sys.exit(f"Rückleitung nicht verwertbar: {problem}\n  {location}")
    print(f"Code erhalten: {code[:8]}…")
    return code


def login_with_browser(authorize_url, state):
    print("\n1) Diese URL im Browser öffnen (dort bei Stud.IP eingeloggt sein):\n")
    print(f"   {authorize_url}\n")
    print("2) 'Zugriff erlauben' klicken. Der Browser springt dann auf")
    print("   studgo://oauth/callback?code=... — viele Browser zeigen das")
    print("   kommentarlos gar nicht an. Passiert nach dem Klick scheinbar")
    print("   nichts, brich hier ab und nutze stattdessen:")
    print("       ./tools/studip-cli.py login --cookie\n")
    print("3) Sonst die studgo://-Adresse aus der Adresszeile kopieren.\n")

    for _ in range(3):
        pasted = input("studgo://-Adresse oder nur der code: ")
        code, problem = extract_code(pasted, state)
        if code:
            return code
        print(f"\n   {problem}\n")
    sys.exit("Abgebrochen.")


def cmd_refresh():
    tok = load_token()
    if not tok.get("refresh_token"):
        sys.exit("Kein refresh_token vorhanden — bitte neu anmelden.")
    new = post_form(TOKEN, {
        "grant_type": "refresh_token",
        "client_id": ENV["STUDIP_CLIENT_ID"],
        "client_secret": ENV["STUDIP_CLIENT_SECRET"],
        "refresh_token": tok["refresh_token"],
    })
    save_token(new)
    print(f"OK — erneuert, expires_in: {new.get('expires_in')}s")


def load_token():
    if not TOKEN_FILE.exists():
        sys.exit("Noch nicht angemeldet — zuerst: ./tools/studip-cli.py login")
    return json.loads(TOKEN_FILE.read_text())


def api_get(path):
    tok = load_token()
    url = path if path.startswith("http") else API + (path if path.startswith("/") else "/" + path)
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {tok['access_token']}",
        "Accept": "application/vnd.api+json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode(errors='replace')[:600]}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "login":
        cmd_login(use_cookie="--cookie" in sys.argv[2:])
    elif cmd == "refresh":
        cmd_refresh()
    elif cmd == "get":
        print(json.dumps(api_get(sys.argv[2]), indent=2, ensure_ascii=False))
    elif cmd == "whoami":
        d = api_get("/v1/users/me")["data"]
        a = d["attributes"]
        print(f"{a.get('formatted-name')}  (id={d['id']}, username={a.get('username')})")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
