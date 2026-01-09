// Suppress baseline-browser-mapping "data is over two months old" warning
// This warning is hardcoded in Next.js's compiled browserslist bundle with no env var check.
// The data timestamp is embedded at build time and becomes stale. Since we can't control
// Next.js's release schedule, we intercept and suppress this specific warning.
const originalWarn = console.warn;
console.warn = (...args) => {
  if (args[0]?.includes?.('[baseline-browser-mapping]')) return;
  originalWarn.apply(console, args);
};

import { createServer } from 'https';
import { parse, fileURLToPath } from 'url';
import next from 'next';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

// Suppress util._extend deprecation warning from third-party dependencies
process.noDeprecation = true;

// Allow self-signed certificates for local Supabase in development
// Suppress the NODE_TLS_REJECT_UNAUTHORIZED warning since this is intentional for local dev
if (process.env.NODE_ENV !== 'production') {
  const originalEmitWarning = process.emitWarning;
  process.emitWarning = (warning, ...args) => {
    if (typeof warning === 'string' && warning.includes('NODE_TLS_REJECT_UNAUTHORIZED')) {
      return;
    }
    originalEmitWarning.call(process, warning, ...args);
  };
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const dev = process.env.NODE_ENV !== 'production';
const hostname = 'dev.tidex.no';
const port = 3000;

// Initialize Next.js app
const app = next({ dev, hostname, port });
const handle = app.getRequestHandler();

const getRepoRootFromGit = () => {
  try {
    const gitCommonDir = execSync('git rev-parse --git-common-dir', {
      cwd: __dirname,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();

    const resolvedGitDir = path.isAbsolute(gitCommonDir)
      ? gitCommonDir
      : path.join(__dirname, gitCommonDir);

    return path.dirname(resolvedGitDir);
  } catch {
    return null;
  }
};

const repoRoot = getRepoRootFromGit();

const certDirCandidates = [
  process.env.TIDEX_CERT_DIR && path.resolve(process.env.TIDEX_CERT_DIR),
  path.join(__dirname, '.cert'),
  repoRoot && path.join(repoRoot, '.cert'),
].filter(Boolean);

const resolveCertPath = (fileName) => {
  for (const dir of certDirCandidates) {
    const candidate = path.join(dir, fileName);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
};

const keyPath = resolveCertPath('dev.tidex.no-key.pem');
const certPath = resolveCertPath('dev.tidex.no.pem');

if (!keyPath || !certPath) {
  throw new Error(
    `Missing TLS dev certificates. Looked in: ${certDirCandidates.join(
      ', ',
    )}. Set TIDEX_CERT_DIR to override.`
  );
}

// HTTPS options with local certificates
const httpsOptions = {
  key: fs.readFileSync(keyPath),
  cert: fs.readFileSync(certPath),
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
