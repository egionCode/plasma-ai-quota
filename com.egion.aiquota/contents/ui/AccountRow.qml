/*
 * AccountRow.qml: um bloco por conta no popup/desktop: nome e plano em cima e, abaixo,
 *   uma QuotaCell por janela de cota (5 horas, semana...), cada uma com o proprio rotulo.
 * Decisoes:
 *   - Layout unico em blocos (escolha do usuario no lugar da tabela larga): funciona
 *     igual em qualquer largura e nao depende de cabecalho de coluna.
 *   - No maximo duas celulas por linha; janelas extras (Opus, Sonnet) quebram para a
 *     linha de baixo em vez de espremer as barras.
 *   - Titulo = e-mail da conta (pedido do usuario): e o que identifica a conta de
 *     verdade; o nome do perfil do clauth fica no tooltip. Sem e-mail (ou com a opcao
 *     desligada, para compartilhar tela) o titulo volta a ser o nome.
 *   - Logo do provedor no lugar da sigla C1/X. Corta o e-mail no meio quando falta
 *     espaco, para o dominio continuar visivel.
 *   - Frescor so aparece quando o dado NAO e ao vivo ("cache, ha 9h"). Ao vivo e o
 *     normal e nao precisa de texto disputando atencao.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: row

    property var account
    property var windowKeys: []
    property real nowMs: Date.now()
    property int warnRemaining: 20
    property bool showRemaining: true
    property bool showEmail: true

    spacing: Kirigami.Units.smallSpacing

    Labels { id: texts }

    function windowFor(key) {
        for (const w of account.windows) if (w.key === key) return w;
        return null;
    }

    // Linha secundaria da conta: plano e, se o dado nao for ao vivo, de quando ele e
    function subtitle() {
        const parts = [];
        if (account.plan) parts.push(account.plan.charAt(0).toUpperCase() + account.plan.slice(1));
        const age = texts.ageText(account.fetchedAt, nowMs);
        if (account.source === "session") parts.push(i18n("last session, %1", age));
        else if (account.stale) parts.push(i18n("cached, %1", age));
        return parts.join(" · ");
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            ProviderIcon {
                provider: row.account.provider
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: row.showEmail && row.account.email !== "" ? row.account.email : row.account.name
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle

                HoverHandler { id: titleHover }
                PlasmaComponents.ToolTip {
                    // Nome do perfil (ex: work_1) so quando o titulo e o e-mail
                    visible: titleHover.hovered && text !== ""
                    text: row.showEmail && row.account.email !== "" && row.account.name !== row.account.email
                        ? i18n("Profile: %1", row.account.name) : ""
                }
            }
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: row.subtitle()
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            color: row.account.stale ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.disabledTextColor
        }
        // Perfil do clauth com login vencido: os numeros sao do ultimo fetch bom
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: !row.account.authOk
            text: i18n("Login expired")
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.negativeTextColor

            HoverHandler { id: authHover }
            PlasmaComponents.ToolTip {
                visible: authHover.hovered
                text: i18n("This profile's login expired in clauth; open clauth to renew it.")
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: Math.max(1, Math.min(2, row.windowKeys.length))
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        Repeater {
            model: row.windowKeys

            QuotaCell {
                required property string modelData
                // Larguras iguais: preferredWidth igual + fillWidth divide o espaco por igual
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                window: row.windowFor(modelData)
                caption: texts.columnLabel(modelData)
                nowMs: row.nowMs
                warnRemaining: row.warnRemaining
                showRemaining: row.showRemaining
            }
        }
    }
}
