// api judge: boots the server on a random port, hits endpoints, checks JSON. node check.cjs <server.cjs> <rung> [--json]
const { spawn } = require('child_process');
const path = require('path');
const file = path.resolve(process.argv[2]);
const rung = parseInt(process.argv[3] || '1', 10);
const asJson = process.argv.includes('--json');
const PORT = 30000 + Math.floor(Math.random() * 5000);
const results = [];
const rec = (id, name, pass, detail = '') => results.push({ id, name, soft: false, pass, detail });
(async () => {
  const srv = spawn('node', [file], { env: { ...process.env, PORT: String(PORT) } });
  const base = `http://127.0.0.1:${PORT}`;
  let up = false;
  for (let i = 0; i < 40; i++) { try { await fetch(base + '/'); up = true; break; } catch { await new Promise(r => setTimeout(r, 150)); } }
  const get = async (p) => { try { const r = await fetch(base + p); let j = null; try { j = await r.json(); } catch {} return { status: r.status, json: j }; } catch { return { status: 0, json: null }; } };
  try {
    if (!up) { rec(1, 'server listens on PORT', false, 'no response'); }
    else {
      const h = await get('/health'); rec(1, 'GET /health -> {ok:true}', !!h.json && h.json.ok === true);
      if (rung >= 2) { const e = await get('/echo?msg=hi'); rec(2, 'GET /echo?msg=hi -> {msg:"hi"}', !!e.json && e.json.msg === 'hi'); }
      if (rung >= 3) { const a = await get('/add?a=2&b=3'); rec(3, 'GET /add?a=2&b=3 -> {sum:5}', !!a.json && a.json.sum === 5); }
      if (rung >= 4) { const n = await get('/does-not-exist'); rec(4, 'unknown path -> HTTP 404', n.status === 404); }
    }
  } finally { srv.kill('SIGKILL'); }
  const c = results.filter(r => r.id <= rung), rungPass = c.every(r => r.pass), score = c.filter(r => r.pass).length;
  if (asJson) console.log(JSON.stringify({ rung, rungPass, score, total: c.length, results: c }, null, 2));
  else { for (const r of c) console.log(`${r.pass ? 'PASS' : 'FAIL'} [hard] R${r.id} ${r.name}${r.detail ? '  (' + r.detail + ')' : ''}`); console.log(`rung ${rung}: ${rungPass ? 'PASS' : 'FAIL'} (${score}/${c.length})`); }
  process.exit(rungPass ? 0 : 1);
})();
