/*
 * CompactRepresentation.qml: no painel, o logo do provedor de cada conta com uma barra
 *   por janela empilhada ao lado. Detalhes (e-mail de cada conta) ficam no tooltip e
 *   no popup; duas contas do mesmo provedor aparecem na mesma ordem do popup.
 * Sinal activated: clique do usuario (main.qml alterna o popup).
 * Decisao: so as duas primeiras janelas de cada conta (5h e 7d) entram no painel; as
 *   semanais por modelo (Opus, Sonnet) so no popup, senao a barra fica fina demais.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "../code/format.mjs" as Fmt

MouseArea {
    id: compact

    property var accounts: []
    property int warnRemaining: 20
    property bool showRemaining: true
    property bool hasError: false
    signal activated()

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool empty: accounts.length === 0

    hoverEnabled: true
    onClicked: activated()

    Layout.minimumWidth: vertical ? -1 : (empty ? height : grid.implicitWidth)
    Layout.minimumHeight: vertical ? (empty ? width : grid.implicitHeight) : -1

    // Sem conta para mostrar: icone (alerta se houve erro)
    Kirigami.Icon {
        visible: compact.empty
        anchors.fill: parent
        source: compact.hasError ? "dialog-warning" : "utilities-system-monitor"
        active: compact.containsMouse
    }

    Grid {
        id: grid
        visible: !compact.empty
        anchors.centerIn: parent
        columns: compact.vertical ? 1 : Math.max(1, compact.accounts.length)
        spacing: Kirigami.Units.smallSpacing * 2

        Repeater {
            model: compact.accounts

            Row {
                id: cell
                required property var modelData
                required property int index
                spacing: Kirigami.Units.smallSpacing
                // Conta com dado velho (cache do clauth, sessao do Codex) fica esmaecida
                opacity: modelData.stale ? 0.6 : 1

                ProviderIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    provider: cell.modelData.provider
                    // Acompanha a altura do painel sem passar do tamanho de icone pequeno
                    width: Math.min(Kirigami.Units.iconSizes.small, compact.height * 0.6)
                    height: width
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.max(2, Kirigami.Units.smallSpacing / 2)

                    Repeater {
                        model: cell.modelData.windows.slice(0, 2)

                        QuotaBar {
                            required property var modelData
                            width: Kirigami.Units.gridUnit * 2
                            height: Math.max(4, Math.round(Kirigami.Units.smallSpacing * 1.5))
                            remainingPct: Fmt.remaining(modelData.used_pct)
                            showRemaining: compact.showRemaining
                            warnRemaining: compact.warnRemaining
                        }
                    }
                }
            }
        }
    }
}
