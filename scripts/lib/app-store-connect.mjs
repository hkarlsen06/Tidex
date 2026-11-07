import { execFile } from 'node:child_process';
import { chmod, copyFile, mkdtemp, readFile, realpath, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseEnv, promisify } from 'node:util';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const store = path.join(root, 'ios/app-store');
export const config = JSON.parse(await readFile(path.join(store, 'config.json'), 'utf8'));
const exec = promisify(execFile);

export async function releaseVersion() {
  const text = await readFile(path.join(root, 'ios/Version.xcconfig'), 'utf8');
  const version = text.match(/^MARKETING_VERSION\s*=\s*(\S+)/m)?.[1];
  if (!version) throw new Error('MARKETING_VERSION is missing from ios/Version.xcconfig');
  return version;
}

export function assertEditable(version) {
  const state = version.attributes.appVersionState || version.attributes.appStoreState;
  if (!['PREPARE_FOR_SUBMISSION', 'INVALID_BINARY', 'REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED'].includes(state)) {
    throw new Error(`Version ${version.attributes.versionString} is ${state}; select an editable version before applying changes.`);
  }
}

export async function withAsc(action, { readOnly = true, authenticate = true } = {}) {
  const binary = process.env.ASC_BIN || 'asc';
  const installed = (await exec(binary, ['version'])).stdout.trim().split(/\s/)[0];
  if (installed !== config.cliVersion) {
    throw new Error(`Tidex requires asc ${config.cliVersion}; found ${installed}. See ios/app-store/README.md.`);
  }
  let env = { ...process.env, ASC_APP_ID: config.appId, ASC_DEFAULT_OUTPUT: 'json', ASC_TELEMETRY_DISABLED: '1', NO_COLOR: '1' };
  let temporary;
  try {
    if (authenticate) {
      const envFile = path.join(store, '.env');
      let saved = {};
      try { saved = parseEnv(await readFile(envFile, 'utf8')); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      env = { ...saved, ...env };
      if (env.ASC_PRIVATE_KEY_PATH) {
        const key = path.resolve(path.dirname(await realpath(envFile).catch(() => envFile)), env.ASC_PRIVATE_KEY_PATH);
        // asc requires a 0600 key. Keep the shared original untouched.
        temporary = await mkdtemp(path.join(os.tmpdir(), 'tidex-asc-key-'));
        const privateKey = path.join(temporary, 'AuthKey.p8');
        await copyFile(key, privateKey);
        await chmod(privateKey, 0o600);
        env.ASC_PRIVATE_KEY_PATH = privateKey;
        env.ASC_BYPASS_KEYCHAIN = '1';
      }
    }
    if (readOnly) env.ASC_READ_ONLY = '1';
    const asc = async args => {
      try {
        const { stdout, stderr } = await exec(binary, args, { cwd: root, env, maxBuffer: 32 * 1024 * 1024 });
        if (stderr) process.stderr.write(stderr);
        return stdout.trim() ? JSON.parse(stdout) : null;
      } catch (error) {
        // asc emits partial upload receipts on failure. Keep them for recovery.
        if (error.stdout) process.stderr.write(error.stdout);
        throw new Error(error.stderr?.trim() || error.message);
      }
    };
    return await action(asc, env, binary);
  } finally {
    if (temporary) await rm(temporary, { recursive: true, force: true });
  }
}

export async function resolveVersion(asc, version) {
  if (!/^\d+(?:\.\d+){1,2}$/.test(version)) throw new Error(`Invalid version: ${version}`);
  const response = await asc(['versions', 'list', '--app', config.appId, '--version', version, '--platform', 'IOS', '--paginate']);
  const matches = response.data.filter(item => item.attributes.versionString === version && item.attributes.platform === 'IOS');
  if (matches.length !== 1) throw new Error(`Expected exactly one iOS ${version} version in App Store Connect, found ${matches.length}.`);
  return matches[0];
}

export async function versionLocalizations(asc, versionID) {
  const response = await asc(['localizations', 'list', '--version', versionID, '--paginate']);
  return new Map(response.data.map(item => [item.attributes.locale, item.id]));
}

export function pngDimensions(bytes, label) {
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))
    || bytes.toString('ascii', 12, 16) !== 'IHDR' || bytes.readUInt32BE(8) !== 13) {
    throw new Error(`${label}: invalid PNG header`);
  }
  if (bytes[25] !== 2) throw new Error(`${label}: expected an opaque RGB PNG`);
  let end = false;
  let imageData = false;
  for (let offset = 8; offset < bytes.length;) {
    if (offset + 12 > bytes.length) throw new Error(`${label}: truncated PNG chunk`);
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (offset + 12 + length > bytes.length) throw new Error(`${label}: truncated ${type} chunk`);
    if (type === 'tRNS') throw new Error(`${label}: PNG transparency is not accepted`);
    if (type === 'IDAT') imageData = true;
    offset += length + 12;
    if (type === 'IEND') { end = offset === bytes.length && length === 0; break; }
  }
  if (!imageData || !end) throw new Error(`${label}: incomplete PNG`);
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

export async function checkPNG(file, sizes) {
  const dimensions = pngDimensions(await readFile(file), file);
  if (!sizes.some(size => size[0] === dimensions[0] && size[1] === dimensions[1])) {
    throw new Error(`${file}: unexpected dimensions ${dimensions.join('x')}`);
  }
}
