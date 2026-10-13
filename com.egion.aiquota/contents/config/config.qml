import QtQuick
import org.kde.plasma.configuration

// "source" resolve relativo a contents/ui/, nao a contents/config/
ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Sources")
        icon: "folder-open"
        source: "configSources.qml"
    }
}
