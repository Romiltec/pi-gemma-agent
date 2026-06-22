#!/usr/bin/env node
// A tiny CLI calculator. Each ladder step adds one operation.
// Invocation: node cli.cjs <op> <a> <b>
const [op, a, b] = process.argv.slice(2);
