// Testes de format.mjs (logica pura de apresentacao). Rodar: node --test tests/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as F from '../com.egion.aiquota/contents/code/format.mjs';

test('remaining arredonda e limita', () => {
    assert.equal(F.remaining(4), 96);
    assert.equal(F.remaining(56.4), 44);
    assert.equal(F.remaining(120), 0);
    assert.equal(F.remaining(undefined), 100);
});

test('severity usa aviso e um quarto dele como critico', () => {
    assert.equal(F.severity(50, 20), 'ok');
    assert.equal(F.severity(20, 20), 'warn');
    assert.equal(F.severity(5, 20), 'critical');
    assert.equal(F.severity(1, 2), 'critical');
});

test('durationLabel', () => {
    assert.equal(F.durationLabel(0), '<1m');
    assert.equal(F.durationLabel(12 * 60000), '12m');
    assert.equal(F.durationLabel((4 * 60 + 37) * 60000), '4h 37m');
    assert.equal(F.durationLabel(3 * 3600000), '3h');
    assert.equal(F.durationLabel((51 * 60) * 60000), '2d 3h');
});

test('untilLabel e ageMs', () => {
    const now = Date.parse('2026-10-13T10:00:00Z');
    assert.equal(F.untilLabel('2026-10-13T15:00:00Z', now), '5h');
    assert.equal(F.untilLabel(null, now), '');
    assert.equal(F.ageMs('2026-10-13T01:00:00Z', now), 9 * 3600000);
    assert.equal(F.ageMs('2026-10-13T10:00:30Z', now), 0, 'relogio adiantado nao gera idade negativa');
    assert.equal(F.ageMs('lixo', now), null);
});

test('resetClock usa os nomes de dia recebidos e cai para ingles sem eles', () => {
    const now = new Date(2026, 9, 13, 10, 0).getTime();
    assert.equal(F.resetClock(new Date(2026, 9, 13, 15, 0).toISOString(), now), '15:00');
    assert.equal(F.resetClock(new Date(2026, 9, 16, 4, 5).toISOString(), now), 'Fri 04:05');
    const pt = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
    assert.equal(F.resetClock(new Date(2026, 9, 16, 4, 5).toISOString(), now, pt), 'sex 04:05');
});

test('worstRemaining pega o menor entre contas e janelas', () => {
    const accs = [{ windows: [{ used_pct: 10 }, { used_pct: 70 }] }, { windows: [] }];
    assert.equal(F.worstRemaining(accs), 30);
    assert.equal(F.worstRemaining([]), 100);
});

test('parseOutput normaliza e rejeita lixo', () => {
    const out = F.parseOutput(JSON.stringify({
        generated_at: 'x',
        accounts: [{ provider: 'claude', name: 'a', windows: [{ key: '5h', used_pct: 1 }], auth_ok: false }],
        errors: [{ source: 'codex', code: 'network' }],
    }));
    assert.equal(out.accounts[0].id, 'claude:a');
    assert.equal(out.accounts[0].authOk, false);
    assert.equal(out.errors.length, 1);
    assert.throws(() => F.parseOutput('sh: python3: not found'), e => e.code === 'parse');
    assert.throws(() => F.parseOutput('{"x":1}'), e => e.code === 'parse');
});

test('buildCommand respeita fontes desligadas e escapa caminhos', () => {
    const cmd = F.buildCommand('', '/p/fetch.py', {
        claudeEnabled: true, claudeCredsPath: "/home/o'neil/c.json",
        clauthEnabled: false, codexEnabled: true, codexHome: '',
    });
    assert.equal(cmd, "'python3' '/p/fetch.py' --claude-creds '/home/o'\\''neil/c.json' --no-clauth");
    assert.match(F.buildCommand('py', 's', { detect: true }), /--no-claude --no-clauth --no-codex --detect$/);
});
