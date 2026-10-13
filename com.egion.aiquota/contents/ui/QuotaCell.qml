/*
 * QuotaCell.qml: uma janela de cota (ex: 5 horas) de uma conta: porcentagem, barra e
 *   tempo ate o reset. Celula da tabela do popup.
 * Decisoes:
 *   - So fontes do tema (Heading, smallFont), nunca tamanho em pontos/pixels proprio:
 *     fonte construida a mao sai em escala diferente da do tema conforme o DPI.
 *     Os digitos da Noto Sans (padrao do Plasma) ja tem largura fixa, entao as
 *     porcentagens alinham sem precisar de font.features.
 *   - Hora absoluta do reset so no tooltip; na celula fica o relativo ("em 4h 12m"),
 *     que e o que responde "quando libera" numa olhada.
 *   - window null = esta conta nao tem essa janela: traco discreto, mantem a grade.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../code/format.mjs" as Fmt

ColumnLayout {
    id: cell

    property var window: null
    property real nowMs: Date.now()
    property int warnRemaining: 20
    property bool showRemaining: true
    // Rotulo da janela dentro da celula; usado so quando a tabela nao tem cabecalho
    property string caption: ""

    readonly property int rem: window ? Fmt.remaining(window.used_pct) : 0
    readonly property string level: Fmt.severity(rem, warnRemaining)

    spacing: Kirigami.Units.smallSpacing / 2

    Labels { id: texts }

    PlasmaComponents.Label {
        visible: cell.caption !== ""
        text: cell.caption
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        visible: cell.window !== null

        // Um degrau acima do titulo do widget: o numero e o dado, o titulo so rotula
        Kirigami.Heading {
            level: 3
            text: (cell.showRemaining ? cell.rem : 100 - cell.rem) + "%"
            font.weight: Font.DemiBold
            color: cell.level === "critical" ? Kirigami.Theme.negativeTextColor
                 : cell.level === "warn" ? Kirigami.Theme.neutralTextColor
                 : Kirigami.Theme.textColor
        }
        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignBaseline
            text: cell.showRemaining ? i18nc("percentage of quota", "left") : i18nc("percentage of quota", "used")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }

    QuotaBar {
        visible: cell.window !== null
        Layout.fillWidth: true
        remainingPct: cell.rem
        showRemaining: cell.showRemaining
        warnRemaining: cell.warnRemaining
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: !cell.window ? "‒"
            : cell.window.resets_at ? i18n("in %1", Fmt.untilLabel(cell.window.resets_at, cell.nowMs))
            : ""
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor

        HoverHandler { id: resetHover }
        PlasmaComponents.ToolTip {
            visible: resetHover.hovered && cell.window !== null && !!cell.window.resets_at
            text: cell.window && cell.window.resets_at
                ? i18n("Resets %1", texts.resetClock(cell.window.resets_at, cell.nowMs)) : ""
        }
    }
}
