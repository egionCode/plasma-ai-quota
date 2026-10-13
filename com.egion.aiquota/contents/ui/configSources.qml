/*
 * configSources.qml: pagina Fontes. Liga/desliga cada fonte e permite apontar o caminho
 *   quando a autodeteccao nao acha (CLAUDE_CONFIG_DIR ou CODEX_HOME fora do padrao,
 *   clauth instalado em outro lugar, Python fora do PATH do plasmashell).
 *   clauth vem primeiro porque e a fonte padrao do Claude; o Claude direto e fallback.
 * Decisao: roda o coletor em modo --detect (sem rede) com os valores AINDA NAO
 *   aplicados, para o usuario ver "Encontrado/Nao encontrado" enquanto digita.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/format.mjs" as Fmt

KCM.SimpleKCM {
    id: page

    property alias cfg_claudeEnabled: claudeCheck.checked
    property alias cfg_claudeCredsPath: claudeField.text
    property alias cfg_clauthEnabled: clauthCheck.checked
    property alias cfg_clauthPath: clauthField.text
    property alias cfg_codexEnabled: codexCheck.checked
    property alias cfg_codexHome: codexField.text
    property alias cfg_pythonPath: pythonInput.text

    // Resultado do --detect; {} ate a primeira resposta
    property var detected: ({})
    property bool detectFailed: false

    readonly property string scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../code/fetch_usage.py").toString().replace(/^file:\/\//, ""))

    function runDetect() {
        detector.connectSource(Fmt.buildCommand(pythonInput.text, scriptPath, {
            claudeEnabled: true, claudeCredsPath: claudeField.text,
            clauthEnabled: true, clauthPath: clauthField.text,
            codexEnabled: true, codexHome: codexField.text,
            detect: true,
        }));
    }

    function info(key) {
        return detected[key] || { path: "", found: null };
    }

    Plasma5Support.DataSource {
        id: detector
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                page.detected = JSON.parse(String(data["stdout"] || "").trim());
                page.detectFailed = false;
            } catch (e) {
                page.detected = {};
                page.detectFailed = true;
            }
        }
    }

    // Espera o usuario parar de digitar antes de rodar a deteccao
    Timer {
        id: detectDebounce
        interval: 400
        onTriggered: page.runDetect()
    }

    Component.onCompleted: runDetect()

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("clauth (multiple Claude accounts)")
        }
        QQC2.CheckBox {
            id: clauthCheck
            Kirigami.FormData.label: i18n("Claude accounts:")
            text: i18n("Use clauth when installed")
        }
        PathField {
            id: clauthField
            Kirigami.FormData.label: i18n("Executable:")
            enabled: clauthCheck.checked
            detectedPath: page.info("clauth").path
            found: page.info("clauth").found
            dialogTitle: i18n("clauth executable")
            onTextChanged: detectDebounce.restart()
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Default source for Claude: shows every clauth profile. Keep \"clauth daemon\" running so usage stays current.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Claude Code (without clauth)")
        }
        QQC2.CheckBox {
            id: claudeCheck
            Kirigami.FormData.label: i18n("Fallback:")
            text: i18n("Read the active account directly when clauth is not available")
        }
        PathField {
            id: claudeField
            Kirigami.FormData.label: i18n("Credentials:")
            enabled: claudeCheck.checked
            detectedPath: page.info("claude").path
            found: page.info("claude").found
            dialogTitle: i18n("Claude Code .credentials.json file")
            onTextChanged: detectDebounce.restart()
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Codex")
        }
        QQC2.CheckBox {
            id: codexCheck
            Kirigami.FormData.label: i18n("ChatGPT account:")
            text: i18n("Show")
        }
        PathField {
            id: codexField
            Kirigami.FormData.label: i18n("Codex folder:")
            enabled: codexCheck.checked
            selectFolder: true
            detectedPath: page.info("codex").path
            found: page.info("codex").found
            dialogTitle: i18n("Codex folder (contains auth.json)")
            onTextChanged: detectDebounce.restart()
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Advanced")
        }
        QQC2.TextField {
            id: pythonInput
            Kirigami.FormData.label: i18n("Python:")
            placeholderText: "python3"
            onTextChanged: detectDebounce.restart()
        }
        QQC2.Label {
            visible: page.detectFailed
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.negativeTextColor
            text: i18n("Could not run the collector with this Python. Use an absolute path, e.g. /usr/bin/python3.")
        }
    }
}
