import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname } from 'node:path';

const root = resolve(process.env.DASHBOARD_ROOT ?? '/app/dashboard');
const deployment = new URL(process.env.NEXT_PUBLIC_DEPLOYMENT_URL);
if (!['http:', 'https:'].includes(deployment.protocol) || deployment.username || deployment.password) {
  throw new Error('NEXT_PUBLIC_DEPLOYMENT_URL must be an HTTP URL without credentials');
}
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff',
  '.webmanifest': 'application/manifest+json',
};

export const server = createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Content-Security-Policy', "frame-ancestors 'self'");
  res.setHeader('Referrer-Policy', 'origin-when-cross-origin');
  res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  if (!['GET', 'HEAD'].includes(req.method)) {
    res.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }
  try {
    const url = new URL(req.url, 'http://dashboard');
    const pathname = decodeURIComponent(url.pathname);
    if (pathname.includes('\0') || pathname.split('/').includes('..')) {
      res.writeHead(400).end();
      return;
    }
    if (pathname !== '/' && pathname.endsWith('/')) {
      res.writeHead(308, { Location: url.pathname.replace(/\/+$/, '') + url.search }).end();
      return;
    }
    let file = resolve(root, `.${pathname}`);
    if (!file.startsWith(`${root}/`) && file !== root) {
      res.writeHead(400).end();
      return;
    }
    if (file === root || pathname.endsWith('/')) file = resolve(file, 'index.html');
    if (!extname(file)) file += '.html';
    if (!(await stat(file)).isFile()) {
      res.writeHead(404).end();
      return;
    }
    let body = await readFile(file);
    if (extname(file) === '.html') {
      body = Buffer.from(body.toString().replace(
        /(<script[^>]*id="__NEXT_DATA__"[^>]*>)([\s\S]*?)(<\/script>)/,
        (_match, start, payload, end) => {
          const data = JSON.parse(payload);
          data.props.pageProps.deploymentUrl = deployment.href.replace(/\/$/, '');
          return start + JSON.stringify(data).replace(/</g, '\\u003c') + end;
        },
      ));
    }
    res.writeHead(200, {
      'Content-Type': types[extname(file)] ?? 'application/octet-stream',
      'Content-Length': body.length,
      'Cache-Control': pathname.startsWith('/_next/static/') ? 'public, max-age=31536000, immutable' : 'no-store',
    });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch (error) {
    const status = error instanceof URIError ? 400 : error.code === 'ENOENT' ? 404 : 500;
    if (status === 500) console.error('Dashboard file request failed', error.code ?? error.name);
    res.writeHead(status).end();
  }
});
server.listen(Number(process.env.PORT ?? 6791), '0.0.0.0');
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => server.close(() => process.exit(0)));
}
