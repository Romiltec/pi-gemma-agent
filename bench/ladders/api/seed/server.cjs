// A tiny zero-dependency Node HTTP API. Each ladder step adds one route.
// It must listen on the port given by process.env.PORT.
const http = require('http');
const port = process.env.PORT || 3000;
http.createServer((req, res) => { res.statusCode = 404; res.end(); }).listen(port);
