import { cp, readdir, stat } from 'node:fs/promises';
import path from 'node:path';

const compareVersions = (left, right) => {
  const a = left.split('.').map(Number);
  const b = right.split('.').map(Number);
  return (a[0] - b[0]) || (a[1] - b[1]) || ((a[2] ?? 0) - (b[2] ?? 0));
};

export async function seedVersionMetadata(metadata, version) {
  const versions = path.join(metadata, 'version');
  const target = path.join(versions, version);
  try {
    if (!(await stat(target)).isDirectory()) throw new Error(`${target} is not a directory`);
    return null;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  let entries;
  try { entries = await readdir(versions, { withFileTypes: true }); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  const previous = entries.filter(entry => entry.isDirectory() && /^\d+(?:\.\d+){1,2}$/.test(entry.name))
    .map(entry => entry.name).filter(name => compareVersions(name, version) < 0).sort(compareVersions).at(-1);
  if (!previous) return null;
  await cp(path.join(versions, previous), target, { recursive: true, force: false, errorOnExist: true });
  return previous;
}
