import { createServer } from 'https';
import { parse, fileURLToPath } from 'url';
import next from 'next';
import fs from 'fs';
import path from 'path';

// Suppress util._extend deprecation warning from third-party dependencies
process.noDeprecation = true;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const dev = process.env.NODE_ENV !== 'production';
const hostname = 'local.tidex.no';
const port = 3000;

// Initialize Next.js app
const app = next({ dev, hostname, port });
const handle = app.getRequestHandler();

// HTTPS options with local certificates
const httpsOptions = {
  key: fs.readFileSync(path.join(__dirname, '.cert', 'local.tidex.no-key.pem')),
  cert: fs.readFileSync(path.join(__dirname, '.cert', 'local.tidex.no.pem')),
};

app.prepare().then(() => {
  createServer(httpsOptions, async (req, res) => {
    try {
      const parsedUrl = parse(req.url, true);
      await handle(req, res, parsedUrl);
    } catch (err) {
      console.error('Error occurred handling', req.url, err);
      res.statusCode = 500;
      res.end('internal server error');
    }
  })
    .once('error', (err) => {
      console.error(err);
      process.exit(1);
    })
    .listen(port, () => {
      console.log(`> Ready on https://${hostname}:${port}`);
    });
});
