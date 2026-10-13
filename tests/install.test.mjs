// Testa o install.sh sem rede: modo --local, atualizacao, remocao e erros de uso.
// PACKAGE_ROOT aponta para uma pasta temporaria, entao a instalacao real nunca e tocada.
// Pulado se o kpackagetool6 nao existir (ex: CI sem Plasma).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../install.sh', import.meta.url));
const hasKpkg = spawnSync('kpackagetool6', ['--help']).status === 0;
const skip = !hasKpkg && 'kpackagetool6 ausente';

const run = (args, root) => spawnSync('bash', [script, ...args], {
    encoding: 'utf8',
    env: { ...process.env, PACKAGE_ROOT: root },
});
const withRoot = fn => {
    const root = mkdtempSync(join(tmpdir(), 'plasmoid-test-'));
    try { fn(root); } finally { rmSync(root, { recursive: true, force: true }); }
};

test('install.sh --help mostra o uso e sai com 0', () => {
    const r = spawnSync('bash', [script, '--help'], { encoding: 'utf8' });
    assert.equal(r.status, 0);
    assert.match(r.stdout, /Uso: install\.sh/);
});

test('install.sh rejeita opcao desconhecida com codigo != 0', () => {
    const r = spawnSync('bash', [script, '--nope'], { encoding: 'utf8' });
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /opcao desconhecida/);
});

test('install.sh --version sem valor falha com mensagem clara', () => {
    const r = spawnSync('bash', [script, '--version'], { encoding: 'utf8' });
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /precisa de um valor/);
});

test('install.sh --local instala, atualiza e remove', { skip }, () => withRoot(root => {
    const pkg = join(root, 'com.egion.aiquota', 'metadata.json');

    let r = run(['--local'], root);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /Instalando/);
    assert.ok(existsSync(pkg), 'metadata.json deveria existir apos instalar');

    r = run(['--local'], root);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /Atualizando/, 'segunda execucao deve atualizar, nao reinstalar');

    r = run(['--uninstall'], root);
    assert.equal(r.status, 0, r.stderr);
    assert.ok(!existsSync(pkg), 'pacote deveria sumir apos --uninstall');
}));

test('install.sh --uninstall sem instalacao previa nao falha', { skip }, () => withRoot(root => {
    const r = run(['--uninstall'], root);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /nao esta instalado/);
}));
