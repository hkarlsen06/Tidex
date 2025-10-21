// Centralized API base resolution
// - In production: ignore any localhost/127.0.0.1 VITE_API_BASE and use same-origin (/api/*)
// - In dev: allow VITE_API_BASE, else use http://localhost:3000 when running on localhost
const V = import.meta.env?.VITE_API_BASE?.trim();
const PROD = Boolean(import.meta.env?.PROD);
const isLocalHost = (u) => /^(https?:\/\/)?(localhost|127\.0\.0\.1)(:\d+)?/i.test(String(u || ''));
const HOSTNAME = (typeof window !== 'undefined' && window.location && window.location.hostname) ? window.location.hostname : '';
const IS_KKARLSEN = /kkarlsen\.dev$/i.test(HOSTNAME);

export const API_BASE =
  (V && !(PROD && isLocalHost(V)))
    ? V
    : (PROD
        ? (IS_KKARLSEN ? 'https://server.kkarlsen.dev' : '') // prod default: direct API origin on kkarlsen.dev; else same-origin
        : (typeof window !== 'undefined' && window.location.hostname === 'localhost'
            ? 'http://localhost:3000' // dev
            : ''));

