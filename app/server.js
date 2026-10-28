// App de exemplo do seminário CI/CD.
// Sem dependências externas: usa só o módulo http do Node.
// Mostra qual cliente, versão e commit estão rodando, e expõe /health e /metrics.

const http = require('node:http');
const os = require('node:os');

const PORT = process.env.PORT || 3000;
const CLIENTE = process.env.CLIENTE || 'local';
const VERSION = process.env.APP_VERSION || '0.0.0-dev';
const COMMIT = process.env.APP_COMMIT || 'local';
const COR = process.env.COR || '#2563eb';
const startedAt = Date.now();

// Contador simples de requisições por rota, no formato do Prometheus
const requests = new Map();
function count(route, status) {
  const key = `${route}|${status}`;
  requests.set(key, (requests.get(key) || 0) + 1);
}

function metrics() {
  const lines = [
    '# HELP app_info Informações da versão em execução',
    '# TYPE app_info gauge',
    `app_info{cliente="${CLIENTE}",version="${VERSION}",commit="${COMMIT}"} 1`,
    '# HELP app_uptime_seconds Tempo desde que o container subiu',
    '# TYPE app_uptime_seconds gauge',
    `app_uptime_seconds{cliente="${CLIENTE}"} ${((Date.now() - startedAt) / 1000).toFixed(0)}`,
    '# HELP app_http_requests_total Requisições recebidas por rota e status',
    '# TYPE app_http_requests_total counter',
  ];
  for (const [key, value] of requests) {
    const [route, status] = key.split('|');
    lines.push(`app_http_requests_total{cliente="${CLIENTE}",route="${route}",status="${status}"} ${value}`);
  }
  return lines.join('\n') + '\n';
}

function page() {
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${CLIENTE} · v${VERSION}</title>
<style>
  body { margin:0; min-height:100vh; display:grid; place-items:center;
         font-family: system-ui, sans-serif; background:#0f172a; color:#e2e8f0; }
  .card { background:#1e293b; border-top:8px solid ${COR}; border-radius:12px;
          padding:32px 40px; min-width:320px; box-shadow:0 10px 30px #0006; }
  h1 { margin:0 0 4px; font-size:28px; }
  .sub { color:#94a3b8; margin-bottom:24px; }
  dl { display:grid; grid-template-columns:auto 1fr; gap:8px 16px; margin:0; }
  dt { color:#94a3b8; } dd { margin:0; font-family: ui-monospace, monospace; }
</style>
</head>
<body>
  <div class="card">
    <h1>${CLIENTE}</h1>
    <div class="sub">Seminário CI/CD · GitHub Actions + Docker</div>
    <dl>
      <dt>Versão</dt><dd>${VERSION}</dd>
      <dt>Commit</dt><dd>${COMMIT}</dd>
      <dt>Container</dt><dd>${os.hostname()}</dd>
      <dt>No ar desde</dt><dd>${new Date(startedAt).toISOString()}</dd>
    </dl>
  </div>
</body>
</html>`;
}

function handler(req, res) {
  const url = req.url.split('?')[0];

  if (url === '/health') {
    count('/health', 200);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok', cliente: CLIENTE, version: VERSION, commit: COMMIT }));
  }

  if (url === '/metrics') {
    res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4' });
    return res.end(metrics());
  }

  if (url === '/') {
    count('/', 200);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(page());
  }

  count('outro', 404);
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Não encontrado');
}

const server = http.createServer(handler);

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`[${CLIENTE}] v${VERSION} (${COMMIT}) ouvindo na porta ${PORT}`);
  });
  // Encerramento limpo quando o Docker para o container
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}

module.exports = { server, handler };
