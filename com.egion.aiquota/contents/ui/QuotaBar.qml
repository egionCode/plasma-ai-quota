/*
 * QuotaBar.qml: barra fina de cota, usada no painel e no popup.
 * Desenhada a mao (e nao PlasmaComponents.ProgressBar) porque a cor precisa mudar com
 * o restante, e o ProgressBar do tema nao aceita cor por instancia.
 * Decisoes:
 *   - Cor normal = cor de destaque do tema (nativo). Amarelo/vermelho so quando a cota
 *     esta acabando: cor e sinal, nao enfeite.
 *   - A largura anima na atualizacao (unico movimento do widget). Kirigami zera
 *     longDuration quando o usuario desliga animacoes no sistema.
 */
import QtQuick
import org.kde.kirigami as Kirigami
import "../code/format.mjs" as Fmt

Item {
    id: bar

    // Porcentagem restante 0..100 (a barra mostra restante ou usado conforme showRemaining)
    property int remainingPct: 100
    property bool showRemaining: true
    property int warnRemaining: 20

    readonly property string level: Fmt.severity(remainingPct, warnRemaining)
    readonly property real fraction: (showRemaining ? remainingPct : 100 - remainingPct) / 100
    readonly property color fillColor: level === "critical" ? Kirigami.Theme.negativeTextColor
                                     : level === "warn" ? Kirigami.Theme.neutralTextColor
                                     : Kirigami.Theme.highlightColor

    implicitHeight: Math.max(3, Math.round(Kirigami.Units.smallSpacing))

    // Trilho: texto do tema bem transparente, funciona em tema claro e escuro
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Kirigami.Theme.textColor
        opacity: 0.12
    }

    Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        // Minimo de uma altura para 1% nao virar um risco invisivel
        width: bar.fraction > 0 ? Math.max(height, parent.width * bar.fraction) : 0
        radius: height / 2
        color: bar.fillColor

        Behavior on width {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: Kirigami.Units.longDuration }
        }
    }
}
