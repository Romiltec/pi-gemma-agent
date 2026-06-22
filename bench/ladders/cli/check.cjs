// cli judge: runs the CLI as a subprocess and checks stdout/exit. node check.cjs <cli.cjs> <rung> [--json]
const { execFileSync } = require('child_process');
const path = require('path');
const file = path.resolve(process.argv[2]);
const rung = parseInt(process.argv[3] || '1', 10);
const asJson = process.argv.includes('--json');
const results = [];
const rec = (id, name, pass, detail = '') => results.push({ id, name, soft: false, pass, detail });
function run(args) {
  try { return { out: execFileSync('node', [file, ...args], { encoding: 'utf8' }).trim(), code: 0 }; }
  catch (e) { return { out: ((e.stdout || '') + (e.stderr || '')).trim(), code: e.status || 1 }; }
}
try {
  rec(1, 'add: cli add 2 3 -> 5', run(['add', '2', '3']).out === '5');
  if (rung >= 2) rec(2, 'sub: cli sub 5 2 -> 3', run(['sub', '5', '2']).out === '3');
  if (rung >= 3) rec(3, 'mul: cli mul 4 3 -> 12', run(['mul', '4', '3']).out === '12');
  if (rung >= 4) { const ok = run(['div', '10', '2']).out === '5'; const z = run(['div', '1', '0']).code !== 0;
    rec(4, 'div: cli div 10 2 -> 5, div by 0 errors (non-zero exit)', ok && z); }
  if (rung >= 5) { const h = run(['--help']).out, n = run([]).out;
    rec(5, 'usage: --help (or no args) prints "Usage"', /usage/i.test(h) || /usage/i.test(n)); }
} catch (e) { rec(rung, 'exception', false, e.message); }
const c = results.filter(r => r.id <= rung), rungPass = c.every(r => r.pass), score = c.filter(r => r.pass).length;
if (asJson) console.log(JSON.stringify({ rung, rungPass, score, total: c.length, results: c }, null, 2));
else { for (const r of c) console.log(`${r.pass ? 'PASS' : 'FAIL'} [hard] R${r.id} ${r.name}${r.detail ? '  (' + r.detail + ')' : ''}`); console.log(`rung ${rung}: ${rungPass ? 'PASS' : 'FAIL'} (${score}/${c.length})`); }
process.exit(rungPass ? 0 : 1);
