"use client";

import {
  AUTH_SYNC_CSRF_COOKIE_MAX_AGE,
  AUTH_SYNC_CSRF_COOKIE_NAME,
} from "./constants";

const COOKIE_PATH = "/auth/callback";

const COOKIE_ATTRIBUTES = [
  `Path=${COOKIE_PATH}`,
  "SameSite=Strict",
  `Max-Age=${AUTH_SYNC_CSRF_COOKIE_MAX_AGE}`,
];

function readCookie(name: string): string | null {
  if (typeof document === "undefined") {
    return null;
  }

  const cookies = document.cookie ? document.cookie.split(";") : [];

  for (const cookie of cookies) {
    const [rawName, ...valueParts] = cookie.trim().split("=");
    if (rawName === name) {
      return valueParts.join("=");
    }
  }

  return null;
}

function writeCookie(name: string, value: string) {
  if (typeof document === "undefined") {
    return;
  }

  const attributes = [...COOKIE_ATTRIBUTES];

  if (typeof window !== "undefined" && window.location.protocol === "https:") {
    attributes.push("Secure");
  }

  document.cookie = `${name}=${value}; ${attributes.join("; ")}`;
}

function generateToken(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  return Math.random().toString(36).slice(2);
}

export function ensureAuthSyncCsrfToken(): string {
  const existing = readCookie(AUTH_SYNC_CSRF_COOKIE_NAME);

  if (existing) {
    return existing;
  }

  const token = generateToken();
  writeCookie(AUTH_SYNC_CSRF_COOKIE_NAME, token);
  return token;
}

export function getAuthSyncCsrfToken(): string | null {
  return readCookie(AUTH_SYNC_CSRF_COOKIE_NAME);
}
