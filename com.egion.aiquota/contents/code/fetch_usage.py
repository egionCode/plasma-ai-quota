#!/usr/bin/env python3
"""
fetch_usage.py: coleta o uso das assinaturas de IA instaladas na maquina e imprime JSON.

Objetivo: ser a unica parte do widget que toca em credenciais. O QML roda este script,
  le o stdout e so recebe porcentagens e horarios, nunca tokens.

Dependencias: so a biblioteca padrao do Python 3 (urllib, json, subprocess, threads).

Fontes:
  - clauth (padrao para Claude quando instalado): `clauth status --json` traz todas as
    contas Claude com o uso que o clauth mantem. Fica atualizado enquanto o
    `clauth daemon` roda; sem ele e cache (o widget mostra a idade e avisa).
  - Claude direto (fallback sem clauth): ~/.claude/.credentials.json (ou
    $CLAUDE_CONFIG_DIR) -> GET api.anthropic.com/api/oauth/usage. So a conta ativa.
  - Codex: ~/.codex/auth.json (ou $CODEX_HOME) -> GET chatgpt.com/backend-api/wham/usage.
    Se o token venceu ou a rede falhou, usa o ultimo "rate_limits" gravado nas sessoes
    (~/.codex/sessions/**/rollout-*.jsonl).

Decisoes nao obvias:
  - SOMENTE LEITURA: nunca renova token. Os refresh tokens sao rotativos; renovar aqui
    invalidaria o token que o Claude Code, o Codex ou o clauth tem guardado e deslogaria
    o usuario. Token vencido vira o erro "expired" e o fallback, quando existe.
  - Os endpoints de uso nao sao APIs publicas documentadas (sao os que as proprias CLIs
    usam). Por isso o parse e defensivo: campo ausente ou formato novo nao derruba as
    outras fontes, so gera um erro "parse" naquela fonte.
  - Janela cujo reset ja passou e reportada com 0% usado: o dado em cache e anterior ao
    reset, entao o valor guardado nao vale mais.
  - Erros nunca carregam corpo de resposta nem headers, para nao vazar token em log.
  - clauth tem prioridade sobre o Claude direto: ele e o dono dos tokens de todas as
    contas e o daemon dele renova token e uso com seguranca. O Claude direto so roda se
    o clauth estiver desligado, ausente ou falhar, para nao duplicar a conta ativa.
  - clauth e Codex rodam em paralelo; o Claude direto so depois, e so no fallback.
  - E-mail de cada conta: Codex e Claude direto leem de arquivo local (id_token e
    ~/.claude.json). Perfis do clauth precisam de GET /api/oauth/profile; o resultado
    fica em cache (~/.cache/plasma-ai-quota/emails.json) por id da conta, entao a
    consulta so acontece na primeira vez ou quando o perfil troca de conta.

Uso:
  fetch_usage.py [--claude-creds PATH] [--codex-home DIR] [--clauth-bin PATH] [--clauth-home DIR]
                 [--no-claude] [--no-codex] [--no-clauth] [--timeout S] [--detect]
"""

import argparse
import base64
import glob
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CLAUDE_PROFILE_URL = "https://api.anthropic.com/api/oauth/profile"
CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"

# Janelas do Claude que interessam, na ordem de exibicao. As demais chaves da resposta
# sao experimentos internos com nomes de codigo e ficam de fora.
# Dado do clauth mais velho que isso conta como parado, mesmo que ele nao marque "stale".
# O daemon atualiza a cada 90 s; 10 min cobre atrasos sem esconder um daemon morto.
CLAUTH_STALE_AFTER_S = 600

CLAUDE_WINDOWS = [
    ("five_hour", "5h"),
    ("seven_day", "7d"),
    ("seven_day_opus", "7d_opus"),
    ("seven_day_sonnet", "7d_sonnet"),
]


class SourceError(Exception):
    """Erro tipado de uma fonte. code e estavel e a UI traduz; detail e so para debug."""

    def __init__(self, code, detail="", path=None):
        super().__init__(detail or code)
        self.code = code
        self.detail = detail
        self.path = path


# --------------------------------------------------------------------------- utilidades

def now_ts():
    return time.time()


def iso(ts):
    """Epoch (s) -> ISO 8601 UTC, ou None."""
    if ts is None:
        return None
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso(value):
    """ISO 8601 -> epoch (s). Aceita 'Z' e fracao de segundo com mais de 6 digitos."""
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def window(key, used_pct, resets_at_ts, now):
    """Janela normalizada. Reset no passado zera o uso (ver cabecalho)."""
    used = max(0.0, min(100.0, float(used_pct or 0)))
    if resets_at_ts is not None and resets_at_ts <= now:
        used = 0.0
        resets_at_ts = None
    return {"key": key, "used_pct": used, "resets_at": iso(resets_at_ts)}


def key_for_seconds(seconds):
    """Duracao da janela -> chave curta (18000 -> '5h', 604800 -> '7d')."""
    seconds = int(seconds or 0)
    if seconds <= 0:
        return "window"
    if seconds % 86400 == 0:
        return "%dd" % (seconds // 86400)
    if seconds % 3600 == 0:
        return "%dh" % (seconds // 3600)
    return "%dm" % (seconds // 60)


def jwt_payload(token):
    """Payload de um JWT sem validar assinatura (so leitura de claims locais)."""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload))
        return data if isinstance(data, dict) else {}
    except (IndexError, ValueError, AttributeError):
        return {}


def jwt_exp(token):
    """Le o 'exp' de um JWT (so para saber se venceu)."""
    return jwt_payload(token).get("exp")


def read_json(path):
    if not path or not os.path.isfile(path):
        raise SourceError("not_found", path=path)
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise SourceError("parse", type(e).__name__, path=path)


def http_get_json(url, headers, timeout):
    """GET -> dict. Mapeia falhas para codigos tipados sem expor a resposta."""
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise SourceError("auth", "HTTP %d" % e.code)
        if e.code == 429:
            raise SourceError("rate_limit", "HTTP 429")
        raise SourceError("http", "HTTP %d" % e.code)
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise SourceError("network", type(e).__name__)
    except ValueError:
        raise SourceError("parse", "resposta nao e JSON")


# ------------------------------------------------------------------- resolucao de caminhos

def default_claude_creds():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return os.path.join(base, ".credentials.json")


def default_codex_home():
    return os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")


def find_clauth(explicit=None):
    """O plasmashell costuma ter PATH sem ~/.cargo/bin e ~/.local/bin; procura la tambem."""
    if explicit:
        return explicit if os.access(explicit, os.X_OK) else None
    found = shutil.which("clauth")
    if found:
        return found
    for cand in ("~/.cargo/bin/clauth", "~/.local/bin/clauth", "/usr/local/bin/clauth"):
        p = os.path.expanduser(cand)
        if os.access(p, os.X_OK):
            return p
    return None


# ------------------------------------------------------------------------------ Claude

def parse_claude_usage(data, now):
    """Resposta de /api/oauth/usage -> lista de janelas (utilization ja vem em 0-100)."""
    if not isinstance(data, dict):
        raise SourceError("parse", "formato inesperado")
    out = []
    for field, key in CLAUDE_WINDOWS:
        w = data.get(field)
        if isinstance(w, dict) and w.get("utilization") is not None:
            out.append(window(key, w["utilization"], parse_iso(w.get("resets_at")), now))
    if not out:
        raise SourceError("parse", "nenhuma janela de uso na resposta")
    return out


def claude_local_email(creds_path):
    """E-mail da conta ativa do Claude Code, gravado por ele em .claude.json.

    Com CLAUDE_CONFIG_DIR o arquivo fica dentro da pasta de config; no padrao fica no
    home (~/.claude.json), fora de ~/.claude. Tenta os dois.
    """
    for path in (os.path.join(os.path.dirname(creds_path), ".claude.json"),
                 os.path.expanduser("~/.claude.json")):
        try:
            with open(path, encoding="utf-8") as f:
                acc = json.load(f).get("oauthAccount") or {}
            if acc.get("emailAddress"):
                return acc["emailAddress"]
        except (OSError, ValueError, AttributeError):
            continue
    return ""


def fetch_claude(creds_path, timeout, now):
    creds = read_json(creds_path)
    oauth = creds.get("claudeAiOauth") if isinstance(creds, dict) else None
    if not isinstance(oauth, dict) or not oauth.get("accessToken"):
        # Login por API key (sem assinatura) nao tem cota de 5h/7d para mostrar
        raise SourceError("no_subscription", path=creds_path)
    expires = oauth.get("expiresAt")
    if expires and expires / 1000 <= now:
        raise SourceError("expired", path=creds_path)
    data = http_get_json(CLAUDE_USAGE_URL, {
        "Authorization": "Bearer " + oauth["accessToken"],
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "plasma-ai-quota",
    }, timeout)
    return {
        "provider": "claude",
        "name": "Claude",
        "email": claude_local_email(creds_path),
        "plan": oauth.get("subscriptionType") or "",
        "source": "live",
        "fetched_at": iso(now),
        "stale": False,
        "active": True,
        "windows": parse_claude_usage(data, now),
    }


# ------------------------------------------------------------------------------ clauth

def parse_clauth_status(data, now):
    """Saida de `clauth status --json` -> (nome do perfil ativo, contas)."""
    if not isinstance(data, dict) or not isinstance(data.get("profiles"), list):
        raise SourceError("parse", "formato inesperado")
    accounts = []
    for p in data["profiles"]:
        if not isinstance(p, dict) or not p.get("name"):
            continue
        harness = p.get("harness") or "claude"
        fetched = parse_iso(p.get("fetched_at"))
        windows = []
        for w in p.get("windows") or []:
            if isinstance(w, dict) and w.get("utilization_pct") is not None:
                windows.append(window(w.get("label") or "window", w["utilization_pct"],
                                      parse_iso(w.get("resets_at")), now))
        accounts.append({
            "provider": "codex" if harness == "codex" else "claude",
            "name": p["name"],
            "plan": p.get("tier") or "",
            "source": "clauth",
            "fetched_at": p.get("fetched_at"),
            # Nao usa fetch_status: com o daemon rodando ele alterna "Fresh"/"Cached" entre
            # as buscas e o dado tem minutos. Vale o "stale" do clauth ou a idade real.
            "stale": bool(p.get("stale")) or fetched is None or now - fetched > CLAUTH_STALE_AFTER_S,
            "active": bool(p.get("active")),
            "auth_ok": p.get("auth_status", "ok") == "ok",
            "windows": windows,
        })
    return data.get("active_profile"), accounts


def fetch_clauth(binary, timeout):
    if not binary:
        raise SourceError("not_found")
    try:
        r = subprocess.run([binary, "status", "--json"], capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise SourceError("network", "clauth demorou demais")
    except OSError as e:
        raise SourceError("not_found", type(e).__name__, path=binary)
    if r.returncode != 0:
        raise SourceError("http", "clauth saiu com %d" % r.returncode, path=binary)
    try:
        return json.loads(r.stdout)
    except ValueError:
        raise SourceError("parse", "saida do clauth nao e JSON", path=binary)


# ------------------------------------------------------------------------------- Codex

def parse_codex_usage(data, now):
    """Resposta de /backend-api/wham/usage -> (plano, janelas)."""
    rl = data.get("rate_limit") if isinstance(data, dict) else None
    if not isinstance(rl, dict):
        raise SourceError("parse", "sem rate_limit")
    out = []
    for name in ("primary_window", "secondary_window"):
        w = rl.get(name)
        if isinstance(w, dict) and w.get("used_percent") is not None:
            out.append(window(key_for_seconds(w.get("limit_window_seconds")),
                              w["used_percent"], w.get("reset_at"), now))
    if not out:
        raise SourceError("parse", "nenhuma janela de uso na resposta")
    return data.get("plan_type") or "", out


def parse_codex_rate_limits(rl, now):
    """Bloco 'rate_limits' gravado nas sessoes (window_minutes, resets_at em epoch)."""
    out = []
    for name in ("primary", "secondary"):
        w = rl.get(name) if isinstance(rl, dict) else None
        if isinstance(w, dict) and w.get("used_percent") is not None:
            out.append(window(key_for_seconds((w.get("window_minutes") or 0) * 60),
                              w["used_percent"], w.get("resets_at"), now))
    return out


def latest_session_rate_limits(codex_home, max_files=20):
    """Ultimo rate_limits gravado nas sessoes mais recentes -> (epoch do registro, bloco).

    Le de tras para frente e para no primeiro achado: sessoes longas tem milhares de
    linhas e so a mais recente importa.
    """
    files = glob.glob(os.path.join(codex_home, "sessions", "**", "rollout-*.jsonl"),
                      recursive=True)
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    for path in files[:max_files]:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in reversed(lines):
            if '"rate_limits"' not in line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            rl = find_key(entry, "rate_limits")
            if isinstance(rl, dict) and (rl.get("primary") or rl.get("secondary")):
                ts = parse_iso(entry.get("timestamp")) or os.path.getmtime(path)
                return ts, rl
    return None, None


def find_key(obj, key):
    """Busca em profundidade: o evento muda de aninhamento entre versoes do Codex."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for v in obj.values():
            found = find_key(v, key)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for v in obj:
            found = find_key(v, key)
            if found is not None:
                return found
    return None


def codex_email(codex_home):
    """E-mail da conta ChatGPT: claim "email" do id_token local (sem rede)."""
    try:
        with open(os.path.join(codex_home, "auth.json"), encoding="utf-8") as f:
            tokens = json.load(f).get("tokens") or {}
        return jwt_payload(tokens.get("id_token") or "").get("email") or ""
    except (OSError, ValueError, AttributeError):
        return ""


def fetch_codex(codex_home, timeout, now):
    """Tenta ao vivo; em falha recuperavel cai para o historico das sessoes.

    Devolve (conta, erro_do_ao_vivo). O erro vai junto mesmo com fallback para a UI
    poder explicar por que o dado nao e ao vivo.
    """
    auth_path = os.path.join(codex_home, "auth.json")
    live_error = None
    plan = ""
    try:
        auth = read_json(auth_path)
        tokens = auth.get("tokens") if isinstance(auth, dict) else None
        if not isinstance(tokens, dict) or not tokens.get("access_token"):
            raise SourceError("no_subscription", path=auth_path)
        exp = jwt_exp(tokens["access_token"])
        if exp and exp <= now:
            raise SourceError("expired", path=auth_path)
        headers = {
            "Authorization": "Bearer " + tokens["access_token"],
            "User-Agent": "plasma-ai-quota",
        }
        if tokens.get("account_id"):
            headers["ChatGPT-Account-Id"] = tokens["account_id"]
        plan, windows = parse_codex_usage(http_get_json(CODEX_USAGE_URL, headers, timeout), now)
        return {
            "provider": "codex", "name": "Codex", "email": codex_email(codex_home),
            "plan": plan, "source": "live",
            "fetched_at": iso(now), "stale": False, "active": True, "windows": windows,
        }, None
    except SourceError as e:
        live_error = e

    ts, rl = latest_session_rate_limits(codex_home)
    if rl is None:
        raise live_error
    return {
        "provider": "codex", "name": "Codex", "email": codex_email(codex_home),
        "plan": plan, "source": "session",
        "fetched_at": iso(ts), "stale": True, "active": True,
        "windows": parse_codex_rate_limits(rl, now),
    }, live_error


# ------------------------------------------------------------------------- orquestracao

def error_entry(source, e):
    return {"source": source, "code": e.code, "detail": e.detail, "path": e.path}


def email_cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "plasma-ai-quota", "emails.json")


def load_email_cache(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_email_cache(path, cache):
    """Grava atomico (tmp + rename): duas instancias do widget nao corrompem o arquivo."""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".%d.tmp" % os.getpid()
        # 0600: e-mail e dado pessoal, so o dono le
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cache, f)
        os.replace(tmp, path)
    except OSError:
        pass  # cache e so otimizacao; sem ele o e-mail e buscado de novo


def clauth_profile_email(profile_dir, cache, timeout, now):
    """E-mail de um perfil do clauth, do cache ou de /api/oauth/profile.

    Chave do cache = id da conta do perfil (account_id.json), nao o nome: se o perfil
    for religado em outra conta, o e-mail antigo nao vale mais. Token vencido ou falha
    de rede devolve "" e tenta de novo no proximo ciclo. Nunca renova token.
    """
    try:
        with open(os.path.join(profile_dir, "account_id.json"), encoding="utf-8") as f:
            account_id = str(json.load(f))
    except (OSError, ValueError):
        return ""
    if cache.get(account_id):
        return cache[account_id]
    try:
        creds = read_json(os.path.join(profile_dir, "credentials.json"))
        oauth = creds.get("claudeAiOauth") or {}
        if not oauth.get("accessToken") or (oauth.get("expiresAt") or 0) / 1000 <= now:
            return ""
        data = http_get_json(CLAUDE_PROFILE_URL, {
            "Authorization": "Bearer " + oauth["accessToken"],
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "plasma-ai-quota",
        }, timeout)
    except (SourceError, AttributeError):
        return ""
    email = ((data.get("account") or {}).get("email") or "") if isinstance(data, dict) else ""
    if email:
        cache[account_id] = email
    return email


def add_clauth_emails(accounts, clauth_home, timeout, now):
    """Preenche "email" nos perfis Claude do clauth (in place)."""
    path = email_cache_path()
    cache = load_email_cache(path)
    before = dict(cache)
    for acc in accounts:
        if acc["provider"] == "claude":
            acc["email"] = clauth_profile_email(
                os.path.join(clauth_home, "profiles", acc["name"]), cache, timeout, now)
    if cache != before:
        save_email_cache(path, cache)


def clauth_daemon_running(binary, timeout):
    """`clauth daemon --status` sai com 0 se ha daemon rodando. Falha conta como "nao"."""
    try:
        return subprocess.run([binary, "daemon", "--status"], capture_output=True,
                              timeout=timeout).returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def collect(args, now=None):
    now = now_ts() if now is None else now
    accounts, errors = [], []
    claude_path = args.claude_creds or default_claude_creds()
    codex_home = args.codex_home or default_codex_home()
    clauth_bin = None if args.no_clauth else find_clauth(args.clauth_bin)
    daemon = None

    with ThreadPoolExecutor(max_workers=3) as pool:
        f_clauth = pool.submit(fetch_clauth, clauth_bin, args.timeout * 2) if clauth_bin else None
        f_daemon = pool.submit(clauth_daemon_running, clauth_bin, args.timeout) if clauth_bin else None
        f_codex = None if args.no_codex else pool.submit(fetch_codex, codex_home, args.timeout, now)

        clauth_ok = False
        if f_clauth:
            try:
                _, clauth_accounts = parse_clauth_status(f_clauth.result(), now)
                add_clauth_emails(clauth_accounts, args.clauth_home or os.path.expanduser("~/.clauth"),
                                  args.timeout, now)
                accounts.extend(clauth_accounts)
                clauth_ok = True
                daemon = f_daemon.result()
            except SourceError as e:
                errors.append(error_entry("clauth", e))
        elif not args.no_clauth and args.clauth_bin:
            # Caminho configurado e invalido e erro; clauth so ausente nao (e opcional)
            errors.append(error_entry("clauth", SourceError("not_found", path=args.clauth_bin)))

        # Fallback: sem clauth utilizavel, consulta a conta ativa do Claude Code direto
        if not clauth_ok and not args.no_claude:
            try:
                accounts.insert(0, fetch_claude(claude_path, args.timeout, now))
            except SourceError as e:
                errors.append(error_entry("claude", e))

        if f_codex:
            try:
                acc, live_err = f_codex.result()
                accounts.append(acc)
                if live_err:
                    errors.append(error_entry("codex_live", live_err))
            except SourceError as e:
                errors.append(error_entry("codex", e))

    for acc in accounts:
        acc["id"] = "%s:%s" % (acc["provider"], acc["name"])
        acc.setdefault("auth_ok", True)
        acc.setdefault("email", "")
    # clauth_daemon: None = clauth nao usado; False = usado mas sem daemon (dado parado)
    return {"generated_at": iso(now), "accounts": accounts, "errors": errors,
            "clauth_daemon": daemon}


def detect(args):
    """Modo --detect: so diz o que foi encontrado, sem rede. Usado na tela de config."""
    claude_path = args.claude_creds or default_claude_creds()
    codex_home = args.codex_home or default_codex_home()
    clauth_bin = find_clauth(args.clauth_bin)
    return {
        "claude": {"path": claude_path, "found": os.path.isfile(claude_path)},
        "codex": {"path": codex_home,
                  "found": os.path.isfile(os.path.join(codex_home, "auth.json"))},
        "clauth": {"path": clauth_bin or args.clauth_bin or "", "found": bool(clauth_bin)},
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--claude-creds", default="")
    ap.add_argument("--codex-home", default="")
    ap.add_argument("--clauth-bin", default="")
    # Pasta de dados do clauth (perfis); so muda se o clauth estiver fora do padrao
    ap.add_argument("--clauth-home", default="")
    ap.add_argument("--no-claude", action="store_true")
    ap.add_argument("--no-codex", action="store_true")
    ap.add_argument("--no-clauth", action="store_true")
    ap.add_argument("--timeout", type=float, default=10.0)
    ap.add_argument("--detect", action="store_true")
    args = ap.parse_args(argv)
    # "~" vindo da tela de config nao e expandido pelo shell (vai entre aspas simples)
    for name in ("claude_creds", "codex_home", "clauth_bin", "clauth_home"):
        setattr(args, name, os.path.expanduser(getattr(args, name)))

    result = detect(args) if args.detect else collect(args)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
