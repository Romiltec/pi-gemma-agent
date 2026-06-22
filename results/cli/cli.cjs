#!/usr/bin/env node
// A tiny CLI calculator. Each ladder step adds one operation.
// Invocation: node cli.cjs <op> <a> <b>
const [op, a, b] = process.argv.slice(2);

if (!op || op === '--help') {
  console.log("Usage: node cli.cjs <op> <a> <b>");
  process.exit(0);
}

const numA = Number(a);
const numB = Number(b);

if (op === 'add') {
  console.log(numA + numB);
}
if (op === 'sub') {
  console.log(numA - numB);
}
if (op === 'mul') {
  console.log(numA * numB);
}
if (op === 'div') {
  if (numB === 0) {
    console.error("Error: Division by zero");
    process.exit(1);
  }
  console.log(numA / numB);
}
