const http = require('node:http'), fs = require('node:fs'), path = require('node:path');
const root = __dirname;
const pages = new Set(['index.html', 'design-review.html', 'app.js', 'app-core.js',
  'calendar-ui.js', 'editor-ui.js', 'ux-ui.js', 'recurrence.js', 'style.css', 'design.css', 'ux.css',
  'store-images.html', 'store-images.css']);
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.zip': 'application/zip' };
http.createServer((req, res) => {
  let name;
  try { name = decodeURIComponent(req.url.split('?')[0]); }
  catch { res.writeHead(400); return res.end('Invalid path'); }
  const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
  const relative = path.relative(root, file).split(path.sep).join('/');
  // Only browser assets are public, never signing keys, source configuration or .git.
  const allowed = file.startsWith(root + path.sep) && !relative.split('/').some(p => p.startsWith('.')) &&
    (pages.has(relative) || ['preview/', 'assets/', 'mobile/assets/fonts/',
      'mobile/store/screenshots/', 'mobile/store/assets/', 'mobile/store/site/'].some(p => relative.startsWith(p)));
  if (!allowed) { res.writeHead(403); return res.end('Forbidden'); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Not found'); }
    res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.end(data);
  });
}).listen(Number(process.env.HANGEOREUM_PREVIEW_PORT || 5173), '127.0.0.1', function () {
  console.log(`첫칸: http://127.0.0.1:${this.address().port}`);
});
