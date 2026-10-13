/*
 * Labels.qml: textos traduziveis que dependem de dados (rotulo de janela, idade, dia
 *   da semana). Ficam aqui, e nao em format.mjs, porque i18n() so existe no QML.
 * Uso: instanciar "Labels { id: texts }" no componente que precisa.
 */
import QtQuick
import "../code/format.mjs" as Fmt

QtObject {
    function windowLabel(key) {
        switch (key) {
        case "5h":        return i18n("Session (5h)");
        case "7d":        return i18n("Weekly");
        case "7d_opus":   return i18n("Weekly Opus");
        case "7d_sonnet": return i18n("Weekly Sonnet");
        default:          return key;
        }
    }

    // Cabecalho de coluna da tabela (mais curto que windowLabel, que fica no painel/tooltip)
    function columnLabel(key) {
        switch (key) {
        case "5h":        return i18n("5 hours");
        case "7d":        return i18n("Week");
        case "7d_opus":   return i18n("Week, Opus");
        case "7d_sonnet": return i18n("Week, Sonnet");
        default:          return key;
        }
    }

    // "just now" ou "9h ago" (com a unidade neutra de Fmt.durationLabel)
    function ageText(isoDate, nowMs) {
        const ms = Fmt.ageMs(isoDate, nowMs);
        if (ms === null) return "";
        if (ms < 60000) return i18n("just now");
        return i18n("%1 ago", Fmt.durationLabel(ms));
    }

    // Abreviacoes dos dias no idioma do sistema, domingo primeiro (Locale.dayName usa 0 = domingo)
    readonly property var dayNames: {
        const out = [];
        for (let i = 0; i < 7; i++) out.push(Qt.locale().dayName(i, Locale.ShortFormat));
        return out;
    }

    function resetClock(isoDate, nowMs) {
        return Fmt.resetClock(isoDate, nowMs, dayNames);
    }
}
