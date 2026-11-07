#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { withAsc, root } from './lib/app-store-connect.mjs';

try {
  await withAsc(async (_asc, env, binary) => {
    const child = spawn(binary, process.argv.slice(2), { cwd: root, env, stdio: 'inherit' });
    process.exitCode = await new Promise((resolve, reject) => {
      child.on('error', reject);
      child.on('exit', (code, signal) => resolve(code ?? (signal ? 1 : 0)));
    });
  }, { readOnly: false });
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
