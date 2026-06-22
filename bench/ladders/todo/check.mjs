// todo judge (Playwright): drives the DOM and reads window.__todo. node check.mjs <todo.html> <rung> [--json]
import { chromium } from 'playwright';
import { pathToFileURL } from 'url';
import { resolve } from 'path';

const file = process.argv[2];
const rung = parseInt(process.argv[3] || '1', 10);
const asJson = process.argv.includes('--json');
if (!file) { console.error('usage: node check.mjs <todo.html> <rung> [--json]'); process.exit(2); }

const results = [];
const rec = (id, name, pass, detail = '') => results.push({ id, name, soft: false, pass, detail });
const browser = await chromium.launch();
const page = await browser.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
const url = pathToFileURL(resolve(file)).href;
const reload = async () => { await page.goto(url); await page.waitForTimeout(150); };
const items = () => page.evaluate(() => (window.__todo && window.__todo.items) || null);
const addItem = async (t) => { await page.fill('#new-todo', t); await page.press('#new-todo', 'Enter'); await page.waitForTimeout(120); };

try {
  await reload();
  { const it = await items(); const hasInput = await page.$('#new-todo');
    rec(1, 'boot: no console errors, #new-todo exists, window.__todo.items is an empty array', errors.length === 0 && !!hasInput && Array.isArray(it) && it.length === 0, `errors=${errors.length} input=${!!hasInput} items=${JSON.stringify(it)}`); }
  if (rung >= 2) { await reload(); await addItem('Buy milk');
    const it = await items(); const rendered = await page.$$eval('.item', els => els.map(e => e.textContent));
    rec(2, "add: typing + Enter pushes {text,done:false} and renders an .item", !!it && it.length === 1 && it[0].text === 'Buy milk' && it[0].done === false && rendered.some(t => t.includes('Buy milk')), `items=${JSON.stringify(it)} rendered=${rendered.length}`); }
  if (rung >= 3) { await reload(); await addItem('Task A'); await page.click('.item span'); await page.waitForTimeout(120);
    const it = await items(); const cls = await page.$eval('.item', e => e.className);
    rec(3, "toggle: clicking an item's text toggles done and adds 'done' class", !!it && it[0].done === true && /done/.test(cls), `done=${it && it[0] && it[0].done} class="${cls}"`); }
  if (rung >= 4) { await reload(); await addItem('Task A'); await page.click('.item .del'); await page.waitForTimeout(120);
    const it = await items(); const n = await page.$$eval('.item', els => els.length);
    rec(4, 'remove: clicking .del removes the item from state and DOM', !!it && it.length === 0 && n === 0, `items=${it && it.length} dom=${n}`); }
  if (rung >= 5) { await reload(); await addItem('A'); await addItem('B'); await page.click('.item span'); await page.waitForTimeout(120);
    const rem = (await page.$eval('#remaining', e => e.textContent)).trim();
    rec(5, '#remaining shows the count of not-done items (here: 1)', rem === '1', `remaining="${rem}"`); }
} catch (e) { rec(rung, 'exception during checks', false, e.message); }

await browser.close();
const c = results.filter(r => r.id <= rung), rungPass = c.every(r => r.pass), score = c.filter(r => r.pass).length;
if (asJson) console.log(JSON.stringify({ rung, rungPass, score, total: c.length, errors, results: c }, null, 2));
else { for (const r of c) console.log(`${r.pass ? 'PASS' : 'FAIL'} [hard] R${r.id} ${r.name}${r.detail ? '  (' + r.detail + ')' : ''}`); if (errors.length) console.log('errors: ' + errors.slice(0, 5).join(' | ')); console.log(`rung ${rung}: ${rungPass ? 'PASS' : 'FAIL'} (${score}/${c.length})`); }
process.exit(rungPass ? 0 : 1);
