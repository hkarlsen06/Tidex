/**
 * Impersonation Cryptographic Utilities
 *
 * Server-side only encryption for admin refresh tokens and
 * signing for impersonation context cookies.
 *
 * Uses AES-256-GCM for encryption and HMAC-SHA256 for signing.
 */
import "server-only";
import { randomBytes, createCipheriv, createDecipheriv, createHmac } from "crypto";

// Environment variable names
const ENC_KEY_ENV = "IMPERSONATION_ENC_KEY";
const SIGN_KEY_ENV = "IMPERSONATION_SIGNING_KEY";

// Current key ID for key rotation readiness
const CURRENT_KEY_ID = "v1";

// Encryption algorithm
const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12; // 96 bits for GCM
const AUTH_TAG_LENGTH = 16; // 128 bits

/**
 * Get the encryption key from environment.
 * Key must be 32 bytes (256 bits) for AES-256.
 */
function getEncryptionKey(): Buffer {
  const keyHex = process.env[ENC_KEY_ENV];
  if (!keyHex) {
    throw new Error(`Missing ${ENC_KEY_ENV} environment variable`);
  }

  const key = Buffer.from(keyHex, "hex");
  if (key.length !== 32) {
    throw new Error(`${ENC_KEY_ENV} must be 64 hex characters (32 bytes)`);
  }

  return key;
}

/**
 * Get the signing key from environment.
 * Key should be at least 32 bytes for HMAC-SHA256.
 */
function getSigningKey(): Buffer {
  const keyHex = process.env[SIGN_KEY_ENV];
  if (!keyHex) {
    throw new Error(`Missing ${SIGN_KEY_ENV} environment variable`);
  }

  const key = Buffer.from(keyHex, "hex");
  if (key.length < 32) {
    throw new Error(`${SIGN_KEY_ENV} must be at least 64 hex characters (32 bytes)`);
  }

  return key;
}

// ============================================================================
// ENCRYPTION (for admin refresh tokens)
// ============================================================================

export interface EncryptedData {
  /** Encrypted ciphertext as base64url */
  ciphertext: string;
  /** Initialization vector as base64url */
  iv: string;
  /** GCM authentication tag as base64url */
  authTag: string;
  /** Key identifier for rotation */
  kid: string;
  /** Encryption algorithm */
  alg: string;
  /** Format version */
  ver: number;
}

/**
 * Encrypt a plaintext string using AES-256-GCM.
 *
 * @param plaintext - The string to encrypt
 * @returns Encrypted data object with all components
 */
export function encrypt(plaintext: string): EncryptedData {
  const key = getEncryptionKey();
  const iv = randomBytes(IV_LENGTH);

  const cipher = createCipheriv(ALGORITHM, key, iv, {
    authTagLength: AUTH_TAG_LENGTH,
  });

  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);

  const authTag = cipher.getAuthTag();

  return {
    ciphertext: encrypted.toString("base64url"),
    iv: iv.toString("base64url"),
    authTag: authTag.toString("base64url"),
    kid: CURRENT_KEY_ID,
    alg: ALGORITHM,
    ver: 1,
  };
}

/**
 * Serialize encrypted data to a compact string format.
 * Format: ver:kid:iv:ciphertext:authTag (all base64url)
 */
export function serializeEncrypted(data: EncryptedData): string {
  return `${data.ver}:${data.kid}:${data.iv}:${data.ciphertext}:${data.authTag}`;
}

/**
 * Parse a serialized encrypted string back to EncryptedData.
 */
export function parseEncrypted(serialized: string): EncryptedData {
  const parts = serialized.split(":");
  if (parts.length !== 5) {
    throw new Error("Invalid encrypted data format");
  }

  const [verStr, kid, iv, ciphertext, authTag] = parts;
  const ver = parseInt(verStr, 10);

  if (isNaN(ver) || ver < 1) {
    throw new Error("Invalid format version");
  }

  return {
    ver,
    kid,
    iv,
    ciphertext,
    authTag,
    alg: ALGORITHM, // Assume current algorithm for v1
  };
}

/**
 * Decrypt an encrypted data object back to plaintext.
 *
 * @param data - The encrypted data object
 * @returns The decrypted plaintext string
 */
export function decrypt(data: EncryptedData): string {
  // For now, we only support v1 with current key
  // Future: support key rotation by looking up key by kid
  if (data.kid !== CURRENT_KEY_ID) {
    throw new Error(`Unsupported key ID: ${data.kid}`);
  }

  const key = getEncryptionKey();
  const iv = Buffer.from(data.iv, "base64url");
  const ciphertext = Buffer.from(data.ciphertext, "base64url");
  const authTag = Buffer.from(data.authTag, "base64url");

  const decipher = createDecipheriv(ALGORITHM, key, iv, {
    authTagLength: AUTH_TAG_LENGTH,
  });

  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]);

  return decrypted.toString("utf8");
}

/**
 * Convenience: encrypt and serialize in one step.
 */
export function encryptAndSerialize(plaintext: string): string {
  return serializeEncrypted(encrypt(plaintext));
}

/**
 * Convenience: parse and decrypt in one step.
 */
export function parseAndDecrypt(serialized: string): string {
  return decrypt(parseEncrypted(serialized));
}

// ============================================================================
// SIGNING (for impersonation context cookies)
// ============================================================================

export interface ImpersonationContext {
  /** Impersonation session ID (UUID) */
  impersonationSessionId: string;
  /** Admin user ID who initiated impersonation */
  adminUserId: string;
  /** Target user ID being impersonated */
  targetUserId: string;
  /** Expiration timestamp (ISO string) */
  expiresAt: string;
  /** Issued at timestamp (ISO string) */
  iat: string;
  /** Unique nonce for correlation */
  nonce: string;
}

/**
 * Sign impersonation context data using HMAC-SHA256.
 *
 * @param context - The impersonation context to sign
 * @returns Base64url signature
 */
export function signContext(context: ImpersonationContext): string {
  const key = getSigningKey();
  const payload = JSON.stringify(context);

  const hmac = createHmac("sha256", key);
  hmac.update(payload);

  return hmac.digest("base64url");
}

/**
 * Verify a signed impersonation context.
 *
 * @param context - The impersonation context
 * @param signature - The signature to verify
 * @returns True if signature is valid
 */
export function verifyContextSignature(
  context: ImpersonationContext,
  signature: string
): boolean {
  const expectedSignature = signContext(context);

  // Constant-time comparison to prevent timing attacks
  if (expectedSignature.length !== signature.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < expectedSignature.length; i++) {
    result |= expectedSignature.charCodeAt(i) ^ signature.charCodeAt(i);
  }

  return result === 0;
}

export interface SignedCookieValue {
  context: ImpersonationContext;
  signature: string;
}

/**
 * Create a signed cookie value from impersonation context.
 */
export function createSignedCookieValue(context: ImpersonationContext): string {
  const signature = signContext(context);
  const payload: SignedCookieValue = { context, signature };
  return Buffer.from(JSON.stringify(payload)).toString("base64url");
}

/**
 * Parse and verify a signed cookie value.
 *
 * @param cookieValue - The base64url encoded cookie value
 * @returns The verified context, or null if invalid
 */
export function parseAndVerifySignedCookie(
  cookieValue: string
): ImpersonationContext | null {
  try {
    const decoded = Buffer.from(cookieValue, "base64url").toString("utf8");
    const parsed = JSON.parse(decoded) as SignedCookieValue;

    if (!parsed.context || !parsed.signature) {
      return null;
    }

    // Verify required fields exist
    const ctx = parsed.context;
    if (
      !ctx.impersonationSessionId ||
      !ctx.adminUserId ||
      !ctx.targetUserId ||
      !ctx.expiresAt ||
      !ctx.iat ||
      !ctx.nonce
    ) {
      return null;
    }

    // Verify signature
    if (!verifyContextSignature(ctx, parsed.signature)) {
      return null;
    }

    // Check expiration
    const expiresAt = new Date(ctx.expiresAt);
    if (isNaN(expiresAt.getTime()) || expiresAt <= new Date()) {
      return null;
    }

    return ctx;
  } catch {
    return null;
  }
}

/**
 * Generate a random nonce for impersonation sessions.
 */
export function generateNonce(): string {
  return randomBytes(16).toString("hex");
}
