/*
 * smoke.qml: carrega format.mjs no motor QML real (V4) e exercita a API.
 * Objetivo: pegar sintaxe/recursos que o Node aceita mas o QML nao. Executado por
 * tests/qml-smoke.test.mjs via `qml6`. Saida: uma linha "RESULT {json}" no stderr.
 */
import QtQuick
import "../../com.egion.aiquota/contents/code/format.mjs" as Fmt

QtObject {
    Component.onCompleted: {
        try {
            const out = {
                rem: Fmt.remaining(4),
                dur: Fmt.durationLabel((4 * 60 + 37) * 60000),
                worst: Fmt.worstRemaining([{ windows: [{ used_pct: 30 }] }]),
                accounts: Fmt.parseOutput('{"accounts":[{"provider":"codex","name":"x"}]}').accounts.length,
                cmd: Fmt.buildCommand("python3", "/s.py", { clauthEnabled: false, claudeEnabled: true, codexEnabled: true }),
                clock: Fmt.resetClock(new Date(Date.now() + 3600000).toISOString(), Date.now()).slice(-5)
            };
            console.log("RESULT " + JSON.stringify(out));
        } catch (e) {
            console.log("RESULT " + JSON.stringify({ error: String(e) }));
        }
        Qt.quit();
    }
}
