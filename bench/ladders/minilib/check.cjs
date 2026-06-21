// minilib judge: requires the produced module and runs cumulative assertions per rung.
// Usage: node check.cjs <lib.js> <rung> [--json]   (exit 0 = rung passed)
const path = require('path');
const file = process.argv[2];
const rung = parseInt(process.argv[3] || '1', 10);
const asJson = process.argv.includes('--json');
if (!file) { console.error('usage: node check.cjs <lib.js> <rung> [--json]'); process.exit(2); }

const results = [];
const rec = (id, name, pass, detail = '') => results.push({ id, name, soft: false, pass, detail });
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

let lib = {};
try {
  const abs = path.resolve(file);
  delete require.cache[abs];
  lib = require(abs);
} catch (e) {
  rec(1, 'module loads without error', false, e.message);
}

const has = (n) => lib && typeof lib[n] === 'function';
try {
  if (results.length === 0) {
    rec(1, 'add(a,b) returns a+b', has('add') && lib.add(2, 3) === 5 && lib.add(-1, 1) === 0);
    if (rung >= 2) rec(2, 'isEven(n)', has('isEven') && lib.isEven(4) === true && lib.isEven(3) === false);
    if (rung >= 3) rec(3, 'reverse(str)', has('reverse') && lib.reverse('abc') === 'cba');
    if (rung >= 4) rec(4, 'clamp(x,lo,hi)', has('clamp') && lib.clamp(5, 0, 10) === 5 && lib.clamp(-1, 0, 10) === 0 && lib.clamp(99, 0, 10) === 10);
    if (rung >= 5) rec(5, 'fib(n) [fib(0)=0,fib(1)=1]', has('fib') && lib.fib(0) === 0 && lib.fib(1) === 1 && lib.fib(10) === 55);
    if (rung >= 6) rec(6, 'fizzbuzz(n)', has('fizzbuzz') && eq(lib.fizzbuzz(5), [1, 2, 'Fizz', 4, 'Buzz']) && lib.fizzbuzz(15)[14] === 'FizzBuzz');
    if (rung >= 7) rec(7, 'unique(arr) preserves order', has('unique') && eq(lib.unique([1, 1, 2, 3, 3, 3]), [1, 2, 3]));
  }
} catch (e) { rec(rung, 'exception during checks', false, e.message); }

const considered = results.filter(r => r.id <= rung);
const rungPass = considered.every(r => r.pass);
const score = considered.filter(r => r.pass).length;
if (asJson) console.log(JSON.stringify({ rung, rungPass, score, total: considered.length, results: considered }, null, 2));
else {
  for (const r of considered) console.log(`${r.pass ? 'PASS' : 'FAIL'} [hard] R${r.id} ${r.name}${r.detail ? '  (' + r.detail + ')' : ''}`);
  console.log(`rung ${rung}: ${rungPass ? 'PASS' : 'FAIL'} (${score}/${considered.length} checks)`);
}
process.exit(rungPass ? 0 : 1);
