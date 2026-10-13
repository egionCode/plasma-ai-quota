/*
 * configGeneral.qml: pagina Geral (intervalo, limite de aviso, restante x usado).
 * Convencao do Plasma: propriedades cfg_<chave> sao copiadas de/para main.xml.
 * Erro de digitacao no sufixo falha em silencio (o valor nunca persiste).
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_refreshMinutes: refreshSpin.value
    property alias cfg_warnRemaining: warnSpin.value
    property alias cfg_showRemaining: remainingRadio.checked
    property alias cfg_showEmail: emailCheck.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh every (min):")
            from: 1
            to: 120
        }
        QQC2.SpinBox {
            id: warnSpin
            Kirigami.FormData.label: i18n("Warn when left (%):")
            from: 1
            to: 90
        }
        QQC2.RadioButton {
            id: remainingRadio
            Kirigami.FormData.label: i18n("Bars show:")
            text: i18n("How much is left")
        }
        QQC2.RadioButton {
            text: i18n("How much was used")
            checked: !remainingRadio.checked
            onToggled: remainingRadio.checked = !checked
        }
        QQC2.CheckBox {
            id: emailCheck
            Kirigami.FormData.label: i18n("Accounts:")
            text: i18n("Show the email of each account")
        }
    }
}
