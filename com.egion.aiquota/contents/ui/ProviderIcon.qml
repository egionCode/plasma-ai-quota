/*
 * ProviderIcon.qml: logo do provedor da conta (Claude, OpenAI/Codex), monocromatico.
 * Decisoes:
 *   - SVGs do Simple Icons (CC0), empacotados em contents/icons: nao dependem de tema
 *     de icones instalado nem de rede. As marcas sao das respectivas empresas.
 *   - isMask pinta com a cor de texto do tema: acompanha claro/escuro, no lugar das
 *     cores de marca, para manter o visual nativo.
 *   - Provedor desconhecido cai num icone generico do tema.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Kirigami.Icon {
    property string provider: ""

    source: provider === "claude" ? Qt.resolvedUrl("../icons/claude.svg")
          : provider === "codex" ? Qt.resolvedUrl("../icons/openai.svg")
          : "utilities-system-monitor"
    isMask: provider === "claude" || provider === "codex"
    color: Kirigami.Theme.textColor
    implicitWidth: Kirigami.Units.iconSizes.small
    implicitHeight: Kirigami.Units.iconSizes.small
}
