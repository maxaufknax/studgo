#!/usr/bin/env python3
"""StudGo Dev-CLI — OAuth2-Flow gegen Stud.IP LUH testen und die JSON:API erkunden.

  ./tools/studip-cli.py login            # PKCE-Flow, Token holen
  ./tools/studip-cli.py refresh          # Access-Token erneuern
  ./tools/studip-cli.py get /v1/users/me # authentifizierter API-Call
  ./tools/studip-cli.py whoami
"""
import base64, hashlib, json, os, secrets, sys, urllib.parse, urllib.request, urllib.error
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


def cmd_login():
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
    print("\n1) Diese URL im Browser öffnen (dort bei Stud.IP eingeloggt sein):\n")
    print(f"   {AUTHORIZE}?{urllib.parse.urlencode(params)}\n")
    print("2) 'Zugriff erlauben' klicken. Der Browser versucht dann, ")
    print("   studgo://oauth/callback?code=... zu öffnen, und zeigt eine")
    print("   Fehlerseite — das ist richtig so, das Schema kennt nur das iPhone.")
    print()
    print("3) Die studgo://-Adresse aus der Adresszeile kopieren.")
    print("   Firefox behält sie dort stehen. Falls dein Browser sie verschluckt:")
    print("   Entwicklerwerkzeuge (F12) → Netzwerk-Tab öffnen, bevor du auf")
    print("   'Zugriff erlauben' klickst — der 302 auf /authorize trägt die")
    print("   Adresse im Location-Header.\n")

    for attempt in range(3):
        pasted = input("studgo://-Adresse oder nur der code: ")
        code, problem = extract_code(pasted, state)
        if code:
            break
        print(f"\n   {problem}\n")
    else:
        sys.exit("Abgebrochen.")

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
        cmd_login()
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
