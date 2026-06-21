// Arcade judge: requires the game to be DRAWN during play + respect the originals' physics.
// Usage: node check.mjs <game.html> <rung> [--json]   (exit 0 = rung passed)
import { chromium } from 'playwright';
import { pathToFileURL } from 'url';
import { resolve } from 'path';

const file = process.argv[2];
const rung = parseInt(process.argv[3] || '1', 10);
const asJson = process.argv.includes('--json');
if (!file) { console.error('usage: node check.mjs <game.html> <rung> [--json]'); process.exit(2); }

const results = [];
const rec = (id, name, soft, pass, detail = '') => results.push({ id, name, soft, pass, detail });

const browser = await chromium.launch();
const page = await browser.newPage();
const errors = [];
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errors.push('console.error: ' + m.text()); });

const url = pathToFileURL(resolve(file)).href;
const getState = () => page.evaluate(() => window.__game);
const press = async k => { await page.keyboard.press(k); await page.waitForTimeout(80); };
const wait = ms => page.waitForTimeout(ms);
const reload = async () => { await page.goto(url); await page.waitForTimeout(300); };
const chash = () => page.evaluate(() => { const c = document.querySelector('canvas'); return c ? c.toDataURL() : ''; });
const canvasNonBlank = () => page.evaluate(() => {
  const c = document.querySelector('canvas'); if (!c) return false;
  const ctx = c.getContext('2d'); if (!ctx) return false;
  const d = ctx.getImageData(0, 0, c.width, c.height).data;
  const seen = new Set();
  for (let i = 0; i < d.length; i += 4 * 97) { seen.add(d[i] + ',' + d[i+1] + ',' + d[i+2]); if (seen.size > 1) return true; }
  return seen.size > 1;
});
const dims = () => page.evaluate(() => { const c = document.querySelector('canvas'); return { w: c.width, h: c.height }; });
async function driveUntil(key, pred, ms = 6000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (key) await press(key); else await wait(120); if (await pred()) return true; } return false; }

try {
  await reload();
  { const st = await getState(); const nb = await canvasNonBlank();
    rec(1, 'boot: no console errors, canvas non-blank, screen=menu', false,
      errors.length === 0 && !!st && st.screen === 'menu' && nb, `errors=${errors.length} screen=${st && st.screen} nonBlank=${nb}`); }
  if (rung >= 2) {
    await reload(); await press('s'); const s1 = await getState();
    await reload(); await press('a'); const s2 = await getState();
    rec(2, 'menu: S->snake, A->arkanoid', false, !!s1 && s1.screen === 'snake' && !!s2 && s2.screen === 'arkanoid', `S=${s1 && s1.screen} A=${s2 && s2.screen}`);
  }
  if (rung >= 3) {
    await reload(); await press('s');
    const init = await getState(); const h0 = await chash();
    let moved = false, anim = false; const t0 = Date.now();
    while (Date.now() - t0 < 1500) {
      const s = await getState();
      if (s && s.snake && init && init.snake && (s.snake.head.x !== init.snake.head.x || s.snake.head.y !== init.snake.head.y)) moved = true;
      if (await chash() !== h0) anim = true;
      if (moved && anim) break; await wait(70);
    }
    await reload(); await press('s');
    const before = await getState(); const dir0 = before && before.snake ? before.snake.dir : null;
    let dirChanged = false;
    if (dir0) { const perp = dir0.x !== 0 ? 'ArrowUp' : 'ArrowLeft';
      for (let i = 0; i < 4 && !dirChanged; i++) { await page.keyboard.press(perp); await wait(50);
        const s = await getState(); if (s && s.snake && s.snake.dir && (s.snake.dir.x !== dir0.x || s.snake.dir.y !== dir0.y)) dirChanged = true; } }
    rec(3, 'snake: RENDERS (canvas animates) + grid movement + responds to arrows', false, anim && moved && dirChanged, `anim=${anim} moved=${moved} dirChanged=${dirChanged}`);
  }
  if (rung >= 4) {
    await reload(); await press('s'); const st0 = await getState(); let grew = false;
    for (let i = 0; i < 60 && !grew; i++) {
      const s = await getState(); if (!s || s.screen !== 'snake' || !s.food || !s.snake) break;
      const hx = s.snake.head.x, hy = s.snake.head.y, fx = s.food.x, fy = s.food.y, d = s.snake.dir;
      if (Math.abs(fx - hx) >= Math.abs(fy - hy)) { if (fx > hx && d.x === 0) await press('ArrowRight'); else if (fx < hx && d.x === 0) await press('ArrowLeft'); else await wait(100); }
      else { if (fy > hy && d.y === 0) await press('ArrowDown'); else if (fy < hy && d.y === 0) await press('ArrowUp'); else await wait(100); }
      const s2 = await getState(); if (s2 && (s2.score > (st0.score || 0) || (s2.snake && s2.snake.len > (st0.snake ? st0.snake.len : 1)))) grew = true;
    }
    rec(4, 'snake: eats food and grows (score/len increase)', true, grew, `grew=${grew}`);
  }
  if (rung >= 5) {
    await reload(); await press('s');
    const over = await driveUntil('ArrowRight', async () => (await getState()).screen === 'gameover', 8000);
    rec(5, 'snake: game over on wall collision', false, over, `gameover=${over}`);
  }
  if (rung >= 6) {
    await reload(); await press('a'); const h0 = await chash(); await wait(500); const anim = (await chash()) !== h0;
    const p0 = await getState(); await press('ArrowLeft'); await press('ArrowLeft'); const pL = await getState();
    await press('ArrowRight'); await press('ArrowRight'); await press('ArrowRight'); const pR = await getState();
    const ok = p0 && p0.paddle && pL && pR && pL.paddle.x < p0.paddle.x && pR.paddle.x > pL.paddle.x;
    rec(6, 'arkanoid: RENDERS (canvas animates) + paddle moves with arrows', false, anim && ok, `anim=${anim} x0=${p0&&p0.paddle&&p0.paddle.x} xL=${pL&&pL.paddle&&pL.paddle.x} xR=${pR&&pR.paddle&&pR.paddle.x}`);
  }
  if (rung >= 7) {
    await reload(); await press('a'); const d = await dims(); const b0 = await getState();
    const sx = b0 && b0.ball ? b0.ball.x : null, sy = b0 && b0.ball ? b0.ball.y : null;
    let vxN = false, vxP = false, vyN = false, vyP = false, inB = true, mv = false;
    for (let i = 0; i < 120; i++) {
      const s = await getState(); if (!s) break; if (s.screen === 'gameover') break;
      if (s.ball && s.paddle) { if (s.ball.x < s.paddle.x) await press('ArrowLeft'); else await press('ArrowRight'); }
      if (s.ball) {
        if (sx !== null && (Math.abs(s.ball.x - sx) > 3 || Math.abs(s.ball.y - sy) > 3)) mv = true;
        if (typeof s.ball.vx === 'number') { if (s.ball.vx > 0) vxP = true; if (s.ball.vx < 0) vxN = true; }
        if (typeof s.ball.vy === 'number') { if (s.ball.vy > 0) vyP = true; if (s.ball.vy < 0) vyN = true; }
        if (s.ball.x < -6 || s.ball.x > d.w + 6 || s.ball.y < -6 || s.ball.y > d.h + 6) inB = false;
      }
      if ((vxN && vxP) || (vyN && vyP)) break;
    }
    const bounced = (vxN && vxP) || (vyN && vyP);
    rec(7, 'arkanoid: ball moves, bounces (velocity inversion), stays in bounds', false, mv && bounced && inB, `moved=${mv} bounce=${bounced} inBounds=${inB}`);
  }
  if (rung >= 8) {
    await reload(); await press('a'); const s0 = await getState(); const b0 = (s0 && s0.bricks) || 0;
    let brickBroke = false, paddleReflect = false;
    for (let i = 0; i < 70 && !(brickBroke && paddleReflect); i++) {
      const s = await getState(); if (!s || s.screen === 'gameover') break;
      if (s.ball && s.paddle) { if (s.ball.x < s.paddle.x) await press('ArrowLeft'); else await press('ArrowRight'); }
      const s2 = await getState();
      if (s2 && typeof s2.bricks === 'number' && s2.bricks < b0) brickBroke = true;
      if (s2 && s2.ball && typeof s2.ball.vy === 'number' && s2.ball.vy < 0 && s2.ball.y > ((await dims()).h * 0.7)) paddleReflect = true;
    }
    rec(8, 'arkanoid: bricks break (count drops) and ball reflects off paddle', true, brickBroke && paddleReflect, `brickBroke=${brickBroke} paddleReflect=${paddleReflect}`);
  }
  if (rung >= 9) {
    await reload(); await press('s');
    const over = await driveUntil('ArrowRight', async () => (await getState()).screen === 'gameover', 8000);
    await press('Enter'); const st = await getState();
    rec(9, 'restart: from game over, Enter returns to menu', false, over && !!st && st.screen === 'menu', `over=${over} afterRestart=${st && st.screen}`);
  }
} catch (e) { rec(rung, 'exception during checks', false, false, e.message); }

await browser.close();
const considered = results.filter(r => r.id <= rung);
const rungPass = considered.filter(r => !r.soft).every(r => r.pass);
const score = considered.filter(r => r.pass).length;
if (asJson) console.log(JSON.stringify({ rung, rungPass, score, total: considered.length, errors, results: considered }, null, 2));
else {
  for (const r of considered) console.log(`${r.pass ? 'PASS' : 'FAIL'} [${r.soft ? 'soft' : 'hard'}] R${r.id} ${r.name}${r.detail ? '  (' + r.detail + ')' : ''}`);
  if (errors.length) { console.log('--- console errors ---'); errors.slice(0, 8).forEach(e => console.log('  ' + e)); }
  console.log(`rung ${rung}: ${rungPass ? 'PASS' : 'FAIL'} (${score}/${considered.length} checks incl. soft)`);
}
process.exit(rungPass ? 0 : 1);
