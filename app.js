// One app, three ways of being "down". The point is not the failures — it is
// which monitors notice them.
//
//   MODE=ok         everything works
//   MODE=dep-down   the app is fine; the thing it depends on is not
//   MODE=blocked    the process answers, but the endpoint users need hangs
const http = require('node:http');
const net = require('node:net');

const MODE = process.env.MODE || 'ok';
const PORT = Number(process.env.PORT || 8080);
const DEP_PORT = 5999;

// The dependency this app cannot work without — a stand-in for the database.
if (MODE === 'ok' || MODE === 'blocked') {
  net.createServer((s) => {
    // The probe below hangs up as soon as it connects, so the server side sees
    // ECONNRESET. Without this handler that unhandled error takes the process down.
    s.on('error', () => {});
    s.end('pong');
  }).listen(DEP_PORT, '127.0.0.1');
}

const dependencyUp = () => new Promise((resolve) => {
  const s = net.connect({ port: DEP_PORT, host: '127.0.0.1' });
  const done = (v) => { s.destroy(); resolve(v); };
  s.setTimeout(500);
  s.on('connect', () => done(true));
  s.on('error', () => done(false));
  s.on('timeout', () => done(false));
});

const server = http.createServer(async (req, res) => {
  const send = (code, body) => {
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(body));
  };

  // The health check almost every generated app ships with. It proves one
  // thing: this process can answer. That is all it proves.
  if (req.url === '/health') return send(200, { status: 'ok' });

  // A health check that asks whether the app can do its job.
  if (req.url === '/healthz') {
    const up = await dependencyUp();
    return send(up ? 200 : 503, { status: up ? 'ok' : 'dependency unreachable' });
  }

  // What a user actually asks for.
  if (req.url === '/orders') {
    if (MODE === 'blocked') { const until = Date.now() + 60_000; while (Date.now() < until) {} }
    const up = await dependencyUp();
    if (!up) {
      // Logged to stdout, which the platform captures. See the second half of the lab.
      console.error(JSON.stringify({ level: 'error', msg: 'orders failed: dependency unreachable' }));
      return send(500, { error: 'could not load orders' });
    }
    return send(200, { orders: [{ id: 1 }, { id: 2 }] });
  }

  send(404, { error: 'not found' });
});

server.listen(PORT, '0.0.0.0', () => console.log(JSON.stringify({ level: 'info', msg: `listening on ${PORT}`, mode: MODE })));
