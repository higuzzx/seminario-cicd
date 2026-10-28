const { test, after } = require('node:test');
const assert = require('node:assert');
const { server } = require('../server');

const ready = new Promise((resolve) => server.listen(0, resolve));
const base = async () => { await ready; return `http://127.0.0.1:${server.address().port}`; };

after(() => server.close());

test('GET /health responde ok', async () => {
  const res = await fetch(`${await base()}/health`);
  assert.strictEqual(res.status, 200);
  const body = await res.json();
  assert.strictEqual(body.status, 'ok');
});

test('GET / mostra a página do cliente', async () => {
  const res = await fetch(`${await base()}/`);
  assert.strictEqual(res.status, 200);
  assert.match(await res.text(), /Seminário CI\/CD/);
});

test('GET /metrics expõe métricas no formato Prometheus', async () => {
  const res = await fetch(`${await base()}/metrics`);
  assert.strictEqual(res.status, 200);
  assert.match(await res.text(), /app_info\{/);
});

test('rota desconhecida retorna 404', async () => {
  const res = await fetch(`${await base()}/nao-existe`);
  assert.strictEqual(res.status, 404);
});
