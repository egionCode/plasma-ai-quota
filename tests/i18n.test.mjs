// Garante que a traducao pt_BR cobre todas as strings do codigo e que o .mo do pacote
// esta compilado a partir do .po atual. Pulado sem gettext instalado.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const hasGettext = spawnSync('msgfmt', ['--version']).status === 0;
const domain = 'plasma_applet_com.egion.aiquota';

test('pt_BR traduz todas as strings extraidas do QML', { skip: !hasGettext && 'gettext ausente' }, () => {
    // Extrai de novo para um .pot temporario: pega string nova que ninguem traduziu
    const dir = mkdtempSync(join(tmpdir(), 'aiq-'));
    const pot = join(dir, 'x.pot');
    const files = spawnSync('find', ['com.egion.aiquota', '-name', '*.qml'], { cwd: root, encoding: 'utf8' })
        .stdout.trim().split('\n');
    const x = spawnSync('xgettext', ['--from-code=UTF-8', '-L', 'JavaScript', '-ki18n:1', '-ki18nc:1c,2',
        '-ki18np:1,2', '-ki18ncp:1c,2,3', '-o', pot, ...files], { cwd: root, encoding: 'utf8' });
    assert.equal(x.status, 0, x.stderr);
    const merged = join(dir, 'm.po');
    spawnSync('msgmerge', ['--quiet', '-o', merged, join(root, 'po/pt_BR.po'), pot]);
    const r = spawnSync('msgfmt', ['--check', '--statistics', '-o', '/dev/null', merged], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    assert.doesNotMatch(r.stderr, /untranslated|fuzzy|não traduzid|aproximad/i, `traducao incompleta: ${r.stderr}`);
});

test('.mo do pacote existe e corresponde ao .po', { skip: !hasGettext && 'gettext ausente' }, () => {
    const mo = join(root, `com.egion.aiquota/contents/locale/pt_BR/LC_MESSAGES/${domain}.mo`);
    assert.ok(existsSync(mo), 'rode scripts/i18n.sh build');
    const dir = mkdtempSync(join(tmpdir(), 'aiq-'));
    const fresh = join(dir, 'f.mo');
    spawnSync('msgfmt', ['-o', fresh, join(root, 'po/pt_BR.po')]);
    assert.ok(readFileSync(fresh).equals(readFileSync(mo)), '.mo desatualizado: rode scripts/i18n.sh build');
});
