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
    print("\n1) Diese URL im Browser öffnen (eingeloggt bei Stud.IP):\n")
    print(f"   {AUTHORIZE}?{urllib.parse.urlencode(params)}\n")
    print("2) Nach 'Zugriff erlauben' leitet Stud.IP auf studgo://oauth/callback?code=...")
    print("   Der Browser kann das Schema nicht öffnen — die URL aus der Fehlermeldung/")
    print("   Adresszeile kopieren und hier einfügen.\n")
    pasted = input("Redirect-URL oder nur der code: ").strip()

    if "code=" in pasted:
        q = urllib.parse.parse_qs(urllib.parse.urlparse(pasted).query)
        code = q["code"][0]
        if q.get("state", [state])[0] != state:
            sys.exit("FEHLER: state stimmt nicht überein (CSRF-Schutz).")
    else:
        code = pasted

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
    print(f"   expires_in: {tok.get('expires_in')}s, refresh_token: {'ja' if tok.get('refresh_token') else 'nein'}")


def cmd_refresh():
    tok = json.loads(TOKEN_FILE.read_text())
    new = post_form(TOKEN, {
        "grant_type": "refresh_token",
        "client_id": ENV["STUDIP_CLIENT_ID"],
        "client_secret": ENV["STUDIP_CLIENT_SECRET"],
        "refresh_token": tok["refresh_token"],
    })
    save_token(new)
    print(f"OK — erneuert, expires_in: {new.get('expires_in')}s")


def api_get(path):
    tok = json.loads(TOKEN_FILE.read_text())
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
