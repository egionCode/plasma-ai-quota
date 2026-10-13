/*
 * main.qml: raiz do plasmoid AI Quota.
 * Objetivo: rodar o coletor (code/fetch_usage.py), guardar o estado (contas, erros,
 *   loading) e alimentar as representacoes compacta e completa.
 * Dependencias: Plasma 6 (plasmoid, plasma5support), Python 3 no sistema, code/format.mjs.
 * Decisoes:
 *   - Credenciais so sao lidas pelo script Python; aqui chegam apenas porcentagens e
 *     horarios. O QML nao consegue ler arquivo local sem XHR com file:// liberado, e
 *     manter tokens fora do motor QML evita que vazem em log de depuracao.
 *   - Dado anterior e mantido quando uma atualizacao falha: piscar para "vazio" a cada
 *     queda de rede seria pior do que mostrar o ultimo valor com a idade dele.
 *   - nowMs anda a cada 30 s so para as contagens regressivas ("reseta em 4h 12m")
 *     ficarem certas sem refazer a consulta.
 */
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/format.mjs" as Fmt

PlasmoidItem {
    id: root

    // --- estado exposto as representacoes ---
    property bool loading: false
    // Falha do coletor inteiro (Python ausente, saida invalida); "" se ok
    property string fatalError: ""
    property var accounts: []
    property var errors: []
    // false = clauth em uso sem daemon: o uso das contas Claude so anda com o clauth aberto
    property var clauthDaemon: null
    property var lastUpdate: null
    property real nowMs: Date.now()

    readonly property int warnRemaining: Plasmoid.configuration.warnRemaining
    readonly property bool showRemaining: Plasmoid.configuration.showRemaining
    readonly property bool showEmail: Plasmoid.configuration.showEmail
    readonly property int worst: Fmt.worstRemaining(accounts)

    // Qt.resolvedUrl devolve file://...; o shell precisa do caminho puro
    readonly property string scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../code/fetch_usage.py").toString().replace(/^file:\/\//, ""))

    // Pede atencao (destaque na bandeja) quando alguma cota esta critica
    Plasmoid.status: accounts.length > 0 && Fmt.severity(worst, warnRemaining) === "critical"
        ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

    // No desktop a vista completa e sempre a preferida, independente do tamanho.
    // Com switchWidth/switchHeight o applet nascia do tamanho do compacto, nunca
    // passava do limite e ficava preso nas barrinhas.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation : null

    // No desktop o proprio widget desenha a moldura de dialogo (ver FullRepresentation),
    // entao o fundo padrao do Plasma sai para nao ficar moldura dupla. Como o desktop
    // sempre mostra a vista completa, a moldura nunca falta.
    Plasmoid.backgroundHints: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground

    toolTipMainText: expanded ? "" : i18n("AI Quota")
    toolTipSubText: expanded ? "" : tooltipText()

    compactRepresentation: CompactRepresentation {
        accounts: root.accounts
        warnRemaining: root.warnRemaining
        showRemaining: root.showRemaining
        hasError: root.fatalError !== "" || (root.accounts.length === 0 && root.errors.length > 0)
        onActivated: root.expanded = !root.expanded
    }
    fullRepresentation: FullRepresentation {
        accounts: root.accounts
        errorMessages: root.errorMessages()
        loading: root.loading
        lastUpdate: root.lastUpdate
        nowMs: root.nowMs
        warnRemaining: root.warnRemaining
        showRemaining: root.showRemaining
        showEmail: root.showEmail
        // Moldura so quando a tabela esta na mesma janela do applet (direto no desktop).
        // No popup ela vive na janela do dialogo, que ja desenha o proprio fundo.
        framed: Plasmoid.formFactor === PlasmaCore.Types.Planar && Window.window === root.Window.window
        onRefreshRequested: root.refresh()
        onConfigureRequested: Plasmoid.internalAction("configure").trigger()
    }

    function tooltipText() {
        if (fatalError !== "") return fatalError;
        if (accounts.length === 0) return loading ? i18n("Loading...") : i18n("No subscription found");
        const lines = [];
        for (let i = 0; i < accounts.length; i++) {
            const a = accounts[i];
            const parts = a.windows.map(w => {
                const r = Fmt.remaining(w.used_pct);
                return Fmt.windowShort(w.key) + " " + (showRemaining ? r : 100 - r) + "%";
            });
            const who = showEmail && a.email !== "" ? a.email : a.name;
            lines.push(who + ": " + (parts.join(" · ") || "-"));
        }
        return lines.join("\n");
    }

    // Nome da fonte para as mensagens
    function sourceName(s) {
        switch (s) {
        case "claude": return "Claude";
        case "clauth": return "clauth";
        default:       return "Codex";
        }
    }

    // Mensagem em portugues para cada (fonte, codigo) tipado do fetch_usage.py
    function errorText(e) {
        const name = sourceName(e.source);
        const path = e.path || "";
        if (e.source === "codex_live") {
            return i18n("Codex: no live data (%1), showing the last usage recorded in the sessions.",
                        reasonText(e.code));
        }
        switch (e.code) {
        case "not_found":
            if (e.source === "clauth") return i18n("clauth not found at %1. Set the path under Sources.", path);
            return i18n("%1: credentials not found at %2. Log in with the CLI or set the path under Sources.", name, path);
        case "expired":
            return i18n("%1: token expired. Open the CLI once so it can renew the login.", name);
        case "auth":
            return i18n("%1: login rejected. Log in again with the CLI.", name);
        case "no_subscription":
            return i18n("%1: logged in with an API key, there is no subscription quota to show.", name);
        default:
            return i18n("%1: %2", name, reasonText(e.code));
        }
    }

    function reasonText(code) {
        switch (code) {
        case "expired":    return i18n("token expired");
        case "auth":       return i18n("login rejected");
        case "network":    return i18n("no connection");
        case "rate_limit": return i18n("request limit reached");
        case "parse":      return i18n("unexpected response format");
        case "not_found":  return i18n("credentials not found");
        default:           return i18n("request failed");
        }
    }

    function errorMessages() {
        const out = [];
        if (fatalError !== "") out.push(fatalError);
        for (const e of errors) out.push(errorText(e));
        if (clauthDaemon === false) {
            out.push(i18n("The clauth daemon is not running, so Claude usage only updates while clauth is open. Run \"clauth daemon\" to keep it current."));
        }
        return out;
    }

    function refresh() {
        if (loading) return;
        loading = true;
        collector.connectSource(Fmt.buildCommand(Plasmoid.configuration.pythonPath, scriptPath, {
            claudeEnabled: Plasmoid.configuration.claudeEnabled,
            claudeCredsPath: Plasmoid.configuration.claudeCredsPath,
            clauthEnabled: Plasmoid.configuration.clauthEnabled,
            clauthPath: Plasmoid.configuration.clauthPath,
            codexEnabled: Plasmoid.configuration.codexEnabled,
            codexHome: Plasmoid.configuration.codexHome,
        }));
    }

    function handleOutput(data) {
        loading = false;
        nowMs = Date.now();
        try {
            const res = Fmt.parseOutput(data["stdout"]);
            accounts = res.accounts;
            errors = res.errors;
            clauthDaemon = res.clauthDaemon;
            fatalError = "";
            lastUpdate = new Date();
        } catch (e) {
            // Primeira linha do stderr ajuda a diagnosticar (ex: "python3: not found")
            const err = String(data["stderr"] || "").trim().split("\n")[0];
            fatalError = i18n("Could not run the collector. Check the Python setting under Sources.")
                + (err ? " (" + err + ")" : "");
        }
    }

    // "executable" roda o comando e devolve stdout/stderr em onNewData. Desconecta logo
    // depois para o mesmo comando poder ser disparado de novo no proximo refresh.
    Plasma5Support.DataSource {
        id: collector
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            root.handleOutput(data);
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // Abrir o popup com dado de mais de 1 min busca de novo: e quando o usuario olha
    onExpandedChanged: {
        if (root.expanded && (!lastUpdate || Date.now() - lastUpdate.getTime() > 60000)) root.refresh();
    }

    // Mudar fonte ou caminho recarrega. Com espera curta: o "Aplicar" da config grava
    // varias chaves seguidas, e disparar na primeira usaria a config pela metade
    Timer {
        id: configDebounce
        interval: 300
        onTriggered: root.refresh()
    }
    Connections {
        target: Plasmoid.configuration
        function onClaudeEnabledChanged() { configDebounce.restart(); }
        function onClaudeCredsPathChanged() { configDebounce.restart(); }
        function onClauthEnabledChanged() { configDebounce.restart(); }
        function onClauthPathChanged() { configDebounce.restart(); }
        function onCodexEnabledChanged() { configDebounce.restart(); }
        function onCodexHomeChanged() { configDebounce.restart(); }
        function onPythonPathChanged() { configDebounce.restart(); }
    }

    Component.onCompleted: refresh()
}
