/*
 * PathField.qml: campo de caminho com botao "Procurar" e linha de status da deteccao.
 * Vazio = autodeteccao; o caminho detectado aparece como placeholder para o usuario
 *   ver o que esta sendo usado sem precisar preencher nada.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: field

    property alias text: input.text
    property string detectedPath: ""
    // null = deteccao ainda nao rodou; true/false = achou ou nao
    property var found: null
    property bool selectFolder: false
    property string dialogTitle: ""

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        QQC2.TextField {
            id: input
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            placeholderText: field.detectedPath !== "" ? field.detectedPath : i18n("detect automatically")
        }
        QQC2.Button {
            icon.name: "document-open-folder"
            onClicked: field.selectFolder ? folderDialog.open() : fileDialog.open()
            QQC2.ToolTip.text: i18n("Browse")
            QQC2.ToolTip.visible: hovered
        }
    }

    QQC2.Label {
        visible: field.found !== null
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: field.found ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
        text: field.found ? i18n("Found: %1", field.detectedPath)
                          : i18n("Not found at %1", field.detectedPath || "-")
    }

    // Dialogs devolvem file:///...; a config guarda caminho puro
    function toPath(url) {
        return decodeURIComponent(url.toString().replace(/^file:\/\//, ""));
    }

    FileDialog {
        id: fileDialog
        title: field.dialogTitle
        onAccepted: input.text = field.toPath(selectedFile)
    }
    FolderDialog {
        id: folderDialog
        title: field.dialogTitle
        onAccepted: input.text = field.toPath(selectedFolder)
    }
}
