#!/usr/bin/env node
const [op, a, b] = process.argv.slice(2);
const x = Number(a), y = Number(b);
if (!op || op === '--help') { console.log('Usage: cli <add|sub|mul|div> <a> <b>'); process.exit(0); }
const ops = { add: () => x + y, sub: () => x - y, mul: () => x * y,
  div: () => { if (y === 0) { console.error('Error: division by zero'); process.exit(1); } return x / y; } };
if (!ops[op]) { console.error('Unknown operation: ' + op); process.exit(1); }
console.log(ops[op]());
