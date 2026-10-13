/*
 * FullRepresentation.qml: vista completa (desktop ou popup). Um bloco por conta
 *   (AccountRow), todos com o mesmo peso, em qualquer largura.
 * Sinais: refreshRequested (botao atualizar), configureRequested (abre a config).
 * Decisoes:
 *   - Sem cabecalho nem titulo: no desktop o widget fica sempre visivel, e o topo
 *     pesava mais que o conteudo. "Atualizado ha X" e as acoes vao num rodape baixo.
 *   - Atualizando: o texto do rodape vira "Atualizando..." e o botao desabilita, em vez
 *     de um spinner (que mudava a altura da linha).
 *   - Janelas = uniao das janelas de todas as contas, em ordem fixa (5h, semana, semana
 *     por modelo). Conta sem uma janela mostra traco, e os blocos ficam alinhados.
 *   - Coluna simples (Repeater) em vez de ListView: sao poucas contas, e a ListView
 *     virtualizada deixava de criar a ultima linha quando a altura do popup mudava.
 *   - Avisos ficam abaixo das contas, nao no lugar delas: uma fonte falhar nao pode
 *     esconder as que funcionaram.
 *   - Primeira carga mostra linhas-esqueleto em vez de spinner no meio do vazio.
 *   - framed=true (tabela direto no desktop): desenha o mesmo fundo e sombra do popup
 *     (dialogs/background do tema) no lugar do fundo padrao de widget. Escolha do
 *     usuario: o visual do popup ficou melhor que a moldura de desktop. Vem do tema
 *     atual, entao acompanha claro/escuro e temas de terceiros.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

Item {
    id: full

    property var accounts: []
    property var errorMessages: []
    property bool loading: false
    property var lastUpdate: null
    property real nowMs: Date.now()
    property int warnRemaining: 20
    property bool showRemaining: true
    property bool showEmail: true
    // Desenhar a moldura de dialogo (so quando a tabela aparece direto no desktop;
    // no popup quem desenha e o proprio dialogo do Plasma)
    property bool framed: false
    signal refreshRequested()
    signal configureRequested()

    Labels { id: texts }

    // Rodape (frescor + acoes) so com o mouse sobre o widget ou foco de teclado num
    // botao. Expande de altura zero e retrai ao sair (pedido do usuario), em vez de
    // ficar invisivel ocupando espaco. As contas ficam ancoradas no topo, entao o
    // rodape cresce para baixo sem empurrar nada para cima.
    // visualFocus (e nao activeFocus): so foco vindo do teclado. activeFocus tambem
    // e ganho por clique ou foco automatico ao abrir o popup, e prenderia o rodape aberto.
    readonly property bool footerShown: hover.hovered || refreshButton.visualFocus
                                        || configureButton.visualFocus

    readonly property real margin: Kirigami.Units.largeSpacing
    // Espaco extra para o conteudo nao encostar na borda desenhada da moldura
    readonly property real frameLeft: framed ? frame.margins.left : 0
    readonly property real frameRight: framed ? frame.margins.right : 0
    readonly property real frameTop: framed ? frame.margins.top : 0
    readonly property real frameBottom: framed ? frame.margins.bottom : 0

    // Ordem fixa das janelas conhecidas; desconhecidas vao no fim, na ordem de chegada
    readonly property var windowKeys: {
        const known = ["5h", "7d", "7d_opus", "7d_sonnet"];
        const seen = {};
        for (const a of accounts) for (const w of a.windows) seen[w.key] = true;
        const keys = known.filter(k => seen[k]);
        for (const k of Object.keys(seen)) if (known.indexOf(k) < 0) keys.push(k);
        return keys;
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 13
    Layout.minimumHeight: Kirigami.Units.gridUnit * 8
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18 + frameLeft + frameRight
    // Altura natural do conteudo, ja com a altura ANIMADA do rodape. Um unico espaco
    // de layout: entre a lista e o rodape.
    readonly property real naturalHeight: footer.Layout.preferredHeight + content.implicitHeight
        + margin * 2 + Kirigami.Units.smallSpacing + frameTop + frameBottom
    // Altura do popup: segue o conteudo, entao o dialogo cresce e encolhe com o rodape
    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 32, naturalHeight)

    // Cartao: moldura, sombra e conteudo com a altura do conteudo, ancorado no topo.
    // No desktop a area do applet tem tamanho fixo; se a moldura preenchesse a area, o
    // rodape abriria num espaco que ja existia e so se veria um fade. Assim a borda
    // desce quando o rodape abre e sobe quando fecha. No popup o cartao ocupa tudo e
    // quem acompanha e o proprio dialogo (Layout.preferredHeight).
    Item {
        id: card
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: full.framed ? Math.min(full.height, full.naturalHeight) : full.height

        // Hover no cartao, nao na area toda: o mouse na parte vazia abaixo dele (no
        // desktop) nao deve abrir o rodape
        HoverHandler { id: hover }

        // Sombra primeiro (fica atras) e por fora dos limites do item, como no popup
        KSvg.FrameSvgItem {
            id: shadow
            visible: full.framed
            imagePath: "dialogs/background"
            prefix: "shadow"
            anchors {
                fill: parent
                leftMargin: -margins.left
                rightMargin: -margins.right
                topMargin: -margins.top
                bottomMargin: -margins.bottom
            }
        }
        KSvg.FrameSvgItem {
            id: frame
            visible: full.framed
            anchors.fill: parent
            imagePath: "dialogs/background"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: full.margin + full.frameLeft
            anchors.rightMargin: full.margin + full.frameRight
            anchors.topMargin: full.margin + full.frameTop
            anchors.bottomMargin: full.margin + full.frameBottom
            spacing: Kirigami.Units.smallSpacing

            // --- linhas ---
            PlasmaComponents.ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                // Trilho vazio a direita quando tudo cabe so ocupa espaco
                QQC2.ScrollBar.vertical.policy: content.implicitHeight > scroll.height
                    ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    id: content
                    // availableWidth desconta a barra de rolagem vertical; sem isso o texto
                    // da direita passava por baixo dela
                    width: scroll.availableWidth
                    spacing: 0

                    Repeater {
                        model: full.accounts

                        ColumnLayout {
                            id: rowItem
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0

                            AccountRow {
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.largeSpacing
                                Layout.bottomMargin: Kirigami.Units.largeSpacing
                                account: rowItem.modelData
                                windowKeys: full.windowKeys
                                nowMs: full.nowMs
                                warnRemaining: full.warnRemaining
                                showRemaining: full.showRemaining
                                showEmail: full.showEmail
                            }
                            Kirigami.Separator {
                                Layout.fillWidth: true
                                visible: rowItem.index < full.accounts.length - 1
                                opacity: 0.35
                            }
                        }
                    }

                    // Esqueleto da primeira carga: forma dos blocos reais, sem numeros
                    Repeater {
                        model: full.loading && full.accounts.length === 0 ? 2 : 0
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.7
                                radius: height / 2
                                color: Kirigami.Theme.textColor
                                opacity: 0.08
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.smallSpacing
                                radius: height / 2
                                color: Kirigami.Theme.textColor
                                opacity: 0.08
                            }
                        }
                    }

                    PlasmaExtras.PlaceholderMessage {
                        visible: full.accounts.length === 0 && !full.loading
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        iconName: "utilities-system-monitor"
                        text: i18n("No subscription found")
                        explanation: i18n("Log in to Claude Code or Codex, or point to the files in the settings.")
                        helpfulAction: QQC2.Action {
                            icon.name: "configure"
                            text: i18n("Configure sources")
                            onTriggered: full.configureRequested()
                        }
                    }

                    Repeater {
                        model: full.errorMessages
                        Kirigami.InlineMessage {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            visible: true
                            type: Kirigami.MessageType.Warning
                            text: modelData
                        }
                    }
                }
            }
            // --- rodape: frescor a esquerda, acoes pequenas a direita ---
            // No rodape e nao no topo (pedido do usuario): as contas abrem o widget e as
            // acoes, que se usa pouco, ficam fora do caminho do olho.
            // Separador + linha num Item que anima a altura; clip esconde a linha enquanto
            // a altura ainda nao chegou ao tamanho natural
            Item {
                id: footer
                Layout.fillWidth: true
                Layout.preferredHeight: full.footerShown
                    ? separator.implicitHeight + footerRow.implicitHeight + Kirigami.Units.smallSpacing : 0
                clip: true
                opacity: full.footerShown ? 1 : 0

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                }
                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }

                Kirigami.Separator {
                    id: separator
                    width: parent.width
                    anchors.top: parent.top
                    visible: full.accounts.length > 0
                    opacity: 0.35
                }
                RowLayout {
                    id: footerRow
                    width: parent.width
                    anchors.bottom: parent.bottom
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: full.lastUpdate !== null
                        text: full.loading ? i18n("Updating...")
                            : full.lastUpdate ? i18n("Updated %1", texts.ageText(full.lastUpdate.toISOString(), full.nowMs)) : ""
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.disabledTextColor
                    }
                    // Botoes do tamanho do texto pequeno: icone small e quase sem padding,
                    // para o rodape nao ficar mais alto que uma linha de texto
                    PlasmaComponents.ToolButton {
                        id: refreshButton
                        enabled: !full.loading
                        icon.name: "view-refresh"
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        padding: Kirigami.Units.smallSpacing / 2
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Refresh")
                        onClicked: full.refreshRequested()
                        PlasmaComponents.ToolTip { text: refreshButton.text }
                    }
                    PlasmaComponents.ToolButton {
                        id: configureButton
                        icon.name: "configure"
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        padding: Kirigami.Units.smallSpacing / 2
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Configure sources")
                        onClicked: full.configureRequested()
                        PlasmaComponents.ToolTip { text: configureButton.text }
                    }
                }
            }
        }
    }
}
