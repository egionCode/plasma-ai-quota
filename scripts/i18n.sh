#!/usr/bin/env bash
#
# i18n.sh: extrai as strings traduziveis e compila as traducoes do widget.
#
# Objetivo: manter po/*.po em dia com o codigo e gerar os .mo que vao dentro do pacote.
# Dependencias: gettext (xgettext, msgmerge, msgfmt).
#
# Uso:
#   scripts/i18n.sh extract   # atualiza po/<dominio>.pot e mescla em cada po/<lingua>.po
#   scripts/i18n.sh build     # compila po/*.po em contents/locale/<lingua>/LC_MESSAGES/
#   scripts/i18n.sh           # os dois, nessa ordem
#
# Decisoes nao obvias:
#   - Dominio "plasma_applet_<id do plugin>": e o nome que o Plasma 6 usa para achar as
#     traducoes de um applet; outro nome e ignorado em silencio.
#   - Os .mo compilados ficam versionados dentro do pacote: assim instalar a partir do
#     clone (install.sh --local) ja sai traduzido, sem exigir gettext do usuario.
#   - QML e lido como JavaScript pelo xgettext (nao existe parser de QML no gettext).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ID="com.egion.aiquota"
DOMAIN="plasma_applet_${PLUGIN_ID}"
PKG="$ROOT/$PLUGIN_ID"
POT="$ROOT/po/$DOMAIN.pot"

extract() {
    # Caminhos relativos ao ROOT para o .pot nao carregar o caminho da maquina de quem gerou
    (cd "$ROOT" && find "$PLUGIN_ID" -name '*.qml' | sort | xargs xgettext \
        --from-code=UTF-8 -L JavaScript \
        -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
        --package-name="$PLUGIN_ID" --msgid-bugs-address="https://github.com/egionCode/plasma-ai-quota/issues" \
        -o "$POT")
    for po in "$ROOT"/po/*.po; do
        [[ -e "$po" ]] || continue
        msgmerge --quiet --update --backup=none "$po" "$POT"
    done
    echo "extraido: $POT"
}

build() {
    for po in "$ROOT"/po/*.po; do
        [[ -e "$po" ]] || continue
        local lang dest
        lang="$(basename "$po" .po)"
        dest="$PKG/contents/locale/$lang/LC_MESSAGES"
        mkdir -p "$dest"
        # --check falha em placeholder %1 faltando ou sobrando na traducao
        msgfmt --check -o "$dest/$DOMAIN.mo" "$po"
        echo "compilado: $lang"
    done
}

case "${1:-all}" in
    extract) extract ;;
    build)   build ;;
    all)     extract; build ;;
    *)       echo "uso: $0 [extract|build]" >&2; exit 1 ;;
esac
