const http = require('http');
const port = process.env.PORT || 3000;
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  res.setHeader('content-type', 'application/json');
  if (u.pathname === '/health') return res.end(JSON.stringify({ ok: true }));
  if (u.pathname === '/echo') return res.end(JSON.stringify({ msg: u.searchParams.get('msg') }));
  if (u.pathname === '/add') return res.end(JSON.stringify({ sum: Number(u.searchParams.get('a')) + Number(u.searchParams.get('b')) }));
  res.statusCode = 404; res.end(JSON.stringify({ error: 'not found' }));
}).listen(port);
