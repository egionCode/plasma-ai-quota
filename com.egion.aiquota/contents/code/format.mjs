/*
 * format.mjs: logica pura de apresentacao (rotulos, tempos, severidade, parse da saida).
 * Objetivo: manter o QML so como cola de UI; tudo aqui e testado em Node e no motor QML.
 * Dependencias: nenhuma.
 * Decisoes:
 *   - Sem async/await, sem Object.fromEntries e sem ?. / ?? (o motor JS do QML do
 *     Plasma 6 nao garante esses recursos; o teste de smoke em qml6 pega regressao).
 *   - Nenhum texto de idioma aqui: modulo .mjs nao enxerga o i18n() do QML. Rotulos
 *     traduziveis ficam no QML; aqui so numeros e unidades neutras ("4h 37m").
 */

// Rotulo curto para o painel, onde cabe pouco: "5h", "7d", "op", "so"
export function windowShort(key) {
    if (key === '7d_opus') return 'op';
    if (key === '7d_sonnet') return 'so';
    return key;
}

// Porcentagem restante inteira, 0..100
export function remaining(usedPct) {
    const used = Number(usedPct) || 0;
    return Math.max(0, Math.min(100, Math.round(100 - used)));
}

// "ok" | "warn" | "critical" a partir do restante e do limite de aviso configurado.
// Critico e um quarto do aviso (min 1%) para nao precisar de uma segunda opcao.
export function severity(remainingPct, warnRemaining) {
    const warn = Number(warnRemaining) || 0;
    const critical = Math.max(1, Math.floor(warn / 4));
    if (remainingPct <= critical) return 'critical';
    if (remainingPct <= warn) return 'warn';
    return 'ok';
}

// Duracao compacta: "2d 3h", "4h 37m", "12m", "<1m"
export function durationLabel(ms) {
    if (!(ms > 0)) return '<1m';
    const min = Math.floor(ms / 60000);
    if (min < 1) return '<1m';
    const d = Math.floor(min / 1440);
    const h = Math.floor((min % 1440) / 60);
    const m = min % 60;
    if (d > 0) return h > 0 ? `${d}d ${h}h` : `${d}d`;
    if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`;
    return `${m}m`;
}

// Tempo ate o reset ("" se a janela nao informa reset)
export function untilLabel(isoDate, nowMs) {
    if (!isoDate) return '';
    const t = Date.parse(isoDate);
    if (isNaN(t)) return '';
    return durationLabel(t - (nowMs === undefined ? Date.now() : nowMs));
}

// Hora local do reset: "15:00" no mesmo dia, "<dia> 04:00" em outro dia.
// dayNames (domingo primeiro) vem do QML via Qt.locale(), para sair no idioma do sistema.
export function resetClock(isoDate, nowMs, dayNames) {
    if (!isoDate) return '';
    const t = new Date(isoDate);
    if (isNaN(t.getTime())) return '';
    const now = new Date(nowMs === undefined ? Date.now() : nowMs);
    const hh = String(t.getHours()).padStart(2, '0');
    const mm = String(t.getMinutes()).padStart(2, '0');
    if (t.toDateString() === now.toDateString()) return `${hh}:${mm}`;
    const days = dayNames || ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return `${days[t.getDay()]} ${hh}:${mm}`;
}

// Idade de um dado em ms (null se a data for invalida). O QML transforma em
// "agora"/"ha 9h" com i18n.
export function ageMs(isoDate, nowMs) {
    if (!isoDate) return null;
    const t = Date.parse(isoDate);
    if (isNaN(t)) return null;
    return Math.max(0, (nowMs === undefined ? Date.now() : nowMs) - t);
}

// Menor restante entre todas as janelas de todas as contas (para o tooltip/icone)
export function worstRemaining(accounts) {
    let worst = 100;
    for (const a of accounts) {
        for (const w of a.windows || []) worst = Math.min(worst, remaining(w.used_pct));
    }
    return worst;
}

// Valida e normaliza o stdout do fetch_usage.py. Lanca Error com code "parse" se nao
// for o JSON esperado (ex: Python ausente imprime erro do shell no lugar).
export function parseOutput(stdout) {
    let data;
    try {
        data = JSON.parse(String(stdout || '').trim());
    } catch (e) {
        const err = new Error('saida invalida do coletor');
        err.code = 'parse';
        throw err;
    }
    if (!data || !Array.isArray(data.accounts)) {
        const err = new Error('saida sem contas');
        err.code = 'parse';
        throw err;
    }
    return {
        generatedAt: data.generated_at || null,
        accounts: data.accounts.map(a => ({
            id: String(a.id || `${a.provider}:${a.name}`),
            provider: String(a.provider || ''),
            name: String(a.name || ''),
            email: String(a.email || ''),
            plan: String(a.plan || ''),
            source: String(a.source || ''),
            fetchedAt: a.fetched_at || null,
            stale: !!a.stale,
            active: !!a.active,
            authOk: a.auth_ok !== false,
            windows: Array.isArray(a.windows) ? a.windows : [],
        })),
        errors: Array.isArray(data.errors) ? data.errors : [],
        // null = clauth nao foi usado; false = usado, mas sem daemon (uso parado)
        clauthDaemon: data.clauth_daemon === undefined ? null : data.clauth_daemon,
    };
}

// Aspas simples para shell: o caminho vem da config e pode ter espaco ou aspas
export function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

// Monta o comando do coletor a partir da config. Campo vazio = autodeteccao.
export function buildCommand(python, script, cfg) {
    const parts = [shellQuote(python || 'python3'), shellQuote(script)];
    if (!cfg.claudeEnabled) parts.push('--no-claude');
    else if (cfg.claudeCredsPath) parts.push('--claude-creds', shellQuote(cfg.claudeCredsPath));
    if (!cfg.clauthEnabled) parts.push('--no-clauth');
    else if (cfg.clauthPath) parts.push('--clauth-bin', shellQuote(cfg.clauthPath));
    if (!cfg.codexEnabled) parts.push('--no-codex');
    else if (cfg.codexHome) parts.push('--codex-home', shellQuote(cfg.codexHome));
    if (cfg.detect) parts.push('--detect');
    // stderr fica separado (o engine executable entrega os dois): um aviso do Python
    // no stderr nao pode corromper o JSON do stdout
    return parts.join(' ');
}
