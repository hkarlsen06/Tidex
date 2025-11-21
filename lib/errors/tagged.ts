/**
 * Effect-TS Tagged Errors
 *
 * Typed errors for the Effect-based architecture. These errors provide:
 * - Type-safe error handling with compile-time checking
 * - Structured error data for better debugging
 * - Integration with Effect's error tracking system
 *
 * Usage:
 * ```typescript
 * yield* Effect.fail(new DatabaseError({
 *   query: "SELECT * FROM users",
 *   cause: error
 * }))
 * ```
 */

import { Data } from "effect";

/**
 * Database-related errors
 * Includes query context for debugging
 */
export class DatabaseError extends Data.TaggedError("DatabaseError")<{
  readonly query?: string;
  readonly table?: string;
  readonly code?: string;
  readonly errorMessage?: string;
  readonly cause?: unknown;
}> {
  get message(): string {
    if (this.errorMessage) {
      return this.errorMessage;
    }
    return `Database error${this.query ? ` in query: ${this.query}` : ""}${this.table ? ` on table: ${this.table}` : ""}`;
  }
}

/**
 * Supabase-specific errors
 * Wraps Supabase client errors with additional context
 */
export class SupabaseError extends Data.TaggedError("SupabaseError")<{
  readonly operation?: string;
  readonly cause: unknown;
}> {
  get message(): string {
    return `Supabase error${this.operation ? ` during ${this.operation}` : ""}`;
  }
}

/**
 * Authentication errors
 * Indicates user authentication failures
 */
export class AuthError extends Data.TaggedError("AuthError")<{
  readonly reason: "unauthorized" | "invalid_session" | "token_expired" | "missing_credentials";
  readonly cause?: unknown;
}> {
  get message(): string {
    switch (this.reason) {
      case "unauthorized":
        return "User is not authenticated";
      case "invalid_session":
        return "Invalid or expired session";
      case "token_expired":
        return "Authentication token has expired";
      case "missing_credentials":
        return "Missing authentication credentials";
      default:
        return "Authentication error";
    }
  }
}

/**
 * Validation errors
 * Used for input validation failures with @effect/schema
 */
export class ValidationError extends Data.TaggedError("ValidationError")<{
  readonly field?: string;
  readonly message: string;
  readonly cause?: unknown;
}> {
  get message(): string {
    return this.field
      ? `Validation error for field '${this.field}': ${this.message}`
      : `Validation error: ${this.message}`;
  }
}

/**
 * Resource not found errors
 * Indicates a requested resource does not exist
 */
export class NotFoundError extends Data.TaggedError("NotFoundError")<{
  readonly resource: string;
  readonly id?: string;
}> {
  get message(): string {
    return this.id
      ? `${this.resource} with id '${this.id}' not found`
      : `${this.resource} not found`;
  }
}

/**
 * Cache operation errors
 * Indicates failures in caching operations
 */
export class CacheError extends Data.TaggedError("CacheError")<{
  readonly operation: "get" | "set" | "invalidate" | "clear";
  readonly key?: string;
  readonly cause: unknown;
}> {
  get message(): string {
    return `Cache ${this.operation} failed${this.key ? ` for key: ${this.key}` : ""}`;
  }
}

/**
 * Configuration errors
 * Indicates missing or invalid configuration
 */
export class ConfigError extends Data.TaggedError("ConfigError")<{
  readonly configKey: string;
  readonly reason: "missing" | "invalid" | "parse_failed";
  readonly cause?: unknown;
}> {
  get message(): string {
    switch (this.reason) {
      case "missing":
        return `Configuration key '${this.configKey}' is missing`;
      case "invalid":
        return `Configuration key '${this.configKey}' is invalid`;
      case "parse_failed":
        return `Failed to parse configuration key '${this.configKey}'`;
      default:
        return `Configuration error for key '${this.configKey}'`;
    }
  }
}

/**
 * Timeout errors
 * Indicates an operation exceeded its time limit
 */
export class TimeoutError extends Data.TaggedError("TimeoutError")<{
  readonly operation: string;
  readonly timeout: string; // e.g., "5 seconds"
}> {
  get message(): string {
    return `Operation '${this.operation}' timed out after ${this.timeout}`;
  }
}

/**
 * Network errors
 * Indicates network-related failures
 */
export class NetworkError extends Data.TaggedError("NetworkError")<{
  readonly url?: string;
  readonly cause: unknown;
}> {
  get message(): string {
    return `Network error${this.url ? ` for URL: ${this.url}` : ""}`;
  }
}

/**
 * Conflict errors
 * Indicates a conflict with existing data (e.g., unique constraint violation)
 */
export class ConflictError extends Data.TaggedError("ConflictError")<{
  readonly resource: string;
  readonly field?: string;
  readonly value?: string;
}> {
  get message(): string {
    if (this.field && this.value) {
      return `${this.resource} already exists with ${this.field} = '${this.value}'`;
    }
    return `${this.resource} conflict detected`;
  }
}

/**
 * Parsing errors
 * Indicates failure to parse data into expected format
 */
export class ParseError extends Data.TaggedError("ParseError")<{
  readonly dataType: string;
  readonly cause: unknown;
}> {
  get message(): string {
    return `Failed to parse ${this.dataType}`;
  }
}

/**
 * AI/LLM provider errors
 * Indicates failures in AI service operations
 */
export class AIError extends Data.TaggedError("AIError")<{
  readonly provider: "openrouter" | "openai" | "anthropic";
  readonly operation: string;
  readonly message: string;
  readonly cause?: unknown;
}> {
  get message(): string {
    return `${this.provider} ${this.operation}: ${this.message}`;
  }
}

/**
 * Type guard to check if an error is an Effect-based tagged error
 */
export function isTaggedError(error: unknown): error is { _tag: string } {
  return (
    typeof error === "object" &&
    error !== null &&
    "_tag" in error &&
    typeof (error as any)._tag === "string"
  );
}

/**
 * Helper to extract error message from any error type
 */
export function getErrorMessage(error: unknown): string {
  if (isTaggedError(error) && "message" in error) {
    return error.message as string;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}
