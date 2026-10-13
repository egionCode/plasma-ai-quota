// Teste de integracao: roda format.mjs no motor QML real via `qml6`.
// Pulado automaticamente se o qml6 nao estiver instalado (ex: CI sem Qt).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const qmlFile = fileURLToPath(new URL('./qml/smoke.qml', import.meta.url));
const hasQml = spawnSync('qml6', ['--version']).status === 0;

test('format.mjs carrega e funciona no motor QML', { skip: !hasQml && 'qml6 ausente' }, () => {
    // QT_FORCE_STDERR_LOGGING faz console.log do QML sair no stderr; offscreen evita janela
    const r = spawnSync('qml6', ['--apptype', 'core', qmlFile], {
        encoding: 'utf8', timeout: 20000,
        env: { ...process.env, QT_FORCE_STDERR_LOGGING: '1', QT_QPA_PLATFORM: 'offscreen' },
    });
    const line = `${r.stdout}\n${r.stderr}`.split('\n').find(l => l.includes('RESULT '));
    assert.ok(line, `sem RESULT; o modulo nao carregou no QML:\n${r.stderr}`);
    const res = JSON.parse(line.slice(line.indexOf('RESULT ') + 7));
    assert.equal(res.error, undefined);
    assert.equal(res.rem, 96);
    assert.equal(res.dur, '4h 37m');
    assert.equal(res.worst, 70);
    assert.equal(res.accounts, 1);
    assert.match(res.cmd, /--no-clauth/);
    assert.equal(res.clock.length, 5);
});
