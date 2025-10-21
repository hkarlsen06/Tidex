import { defineConfig } from 'vite';

export default defineConfig({
  root: '.',
  base: '/',
  server: { port: 5174 },
  preview: { port: 5174 }
});