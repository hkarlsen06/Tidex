import { createServer } from 'https';
import { parse, fileURLToPath } from 'url';
import next from 'next';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

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

const keyPath = resolveCertPath('local.tidex.no-key.pem');
const certPath = resolveCertPath('local.tidex.no.pem');

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
