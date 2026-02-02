/**
 * River Streaming Types
 *
 * Adapted from @davis7dotsh/river-core for Next.js App Router
 * Core types for building type-safe streaming interfaces
 */

import type { Result } from "neverthrow";
import type { ZodSchema } from "zod";

/**
 * Special chunk type marker
 */
export const RIVER_SPECIAL_TYPE_KEY = "RIVER_SPECIAL_TYPE_KEY" as const;

/**
 * Special chunk types for stream lifecycle events
 */
export type RiverSpecialChunkType =
  | "stream_start"
  | "stream_end"
  | "stream_error"
  | "stream_fatal_error";

/**
 * Stream start metadata
 */
export type StreamStartSpecial = {
  [RIVER_SPECIAL_TYPE_KEY]: "stream_start";
  streamRunId: string;
  encodedResumptionToken: string;
};

/**
 * Stream end metadata
 */
export type StreamEndSpecial = {
  [RIVER_SPECIAL_TYPE_KEY]: "stream_end";
  totalChunks: number;
  totalTimeMs: number;
};

/**
 * Stream error (non-fatal)
 */
export type StreamErrorSpecial = {
  [RIVER_SPECIAL_TYPE_KEY]: "stream_error";
  error: RiverErrorJSON;
};

/**
 * Stream fatal error (closes stream)
 */
export type StreamFatalErrorSpecial = {
  [RIVER_SPECIAL_TYPE_KEY]: "stream_fatal_error";
  error: RiverErrorJSON;
};

/**
 * Union of all special chunk types
 */
export type RiverSpecialChunk =
  | StreamStartSpecial
  | StreamEndSpecial
  | StreamErrorSpecial
  | StreamFatalErrorSpecial;

/**
 * Stream item types
 */
export type RiverStreamItem<TChunk> =
  | { type: "chunk"; chunk: TChunk }
  | { type: "special"; special: RiverSpecialChunk }
  | { type: "aborted" };

/**
 * Error types for River operations
 */
export type RiverErrorType =
  | "custom"
  | "stream"
  | "network"
  | "storage"
  | "unknown"
  | "internal";

/**
 * Serializable error format
 */
export type RiverErrorJSON = {
  message: string;
  type: RiverErrorType;
  context?: Record<string, unknown>;
};

/**
 * River Error class
 */
export class RiverError extends Error {
  readonly type: RiverErrorType;
  readonly context?: Record<string, unknown>;

  constructor(
    message: string,
    type: RiverErrorType = "unknown",
    context?: Record<string, unknown>
  ) {
    super(message);
    this.name = "RiverError";
    this.type = type;
    this.context = context;
  }

  toJSON(): RiverErrorJSON {
    return {
      message: this.message,
      type: this.type,
      context: this.context,
    };
  }

  static fromJSON(json: RiverErrorJSON): RiverError {
    return new RiverError(json.message, json.type, json.context);
  }
}

/**
 * Stream control methods available in runner function
 */
export type RiverStreamMethods<TChunk> = {
  appendChunk: (chunk: TChunk) => Promise<void>;
  appendError: (error: RiverError) => Promise<void>;
  sendFatalErrorAndClose: (error: RiverError) => Promise<void>;
  close: () => Promise<void>;
};

/**
 * Runner function context
 */
export type RiverRunnerContext<TInput, TChunk, TAdapterRequest> = {
  input: TInput;
  stream: RiverStreamMethods<TChunk>;
  abortSignal: AbortSignal;
  adapterRequest: TAdapterRequest;
};

/**
 * Runner function type
 */
export type RiverRunnerFn<TInput, TChunk, TAdapterRequest> = (
  context: RiverRunnerContext<TInput, TChunk, TAdapterRequest>
) => Promise<void>;

/**
 * Resumption token data
 */
export type ResumptionTokenData = {
  providerId: string;
  routerStreamKey: string;
  streamStorageId: string;
  streamRunId: string;
};

/**
 * Provider interface
 */
export type RiverProvider = {
  readonly isResumable: boolean;
  readonly providerId: string;
  startStream: <TInput, TChunk, TAdapterRequest>(
    input: TInput,
    adapterRequest: TAdapterRequest,
    runnerFn: RiverRunnerFn<TInput, TChunk, TAdapterRequest>,
    abortController: AbortController
  ) => ReadableStream<RiverStreamItem<TChunk>>;
  resumeStream?: <TChunk>(
    resumptionToken: ResumptionTokenData,
    lastId?: string
  ) => Result<ReadableStream<RiverStreamItem<TChunk>>, RiverError>;
};

/**
 * Stream definition (builder pattern output)
 */
export type RiverStreamDefinition<TInput, TChunk, TAdapterRequest> = {
  inputSchema: ZodSchema<TInput>;
  provider: RiverProvider;
  runner: RiverRunnerFn<TInput, TChunk, TAdapterRequest>;
};

/**
 * Router type (collection of streams)
 */
export type RiverRouter = Record<string, RiverStreamDefinition<any, any, any>>;

/**
 * Extract input type from stream definition
 */
export type InferRiverStreamInputType<T> =
  T extends RiverStreamDefinition<infer TInput, any, any> ? TInput : never;

/**
 * Extract chunk type from stream definition
 */
export type InferRiverStreamChunkType<T> =
  T extends RiverStreamDefinition<any, infer TChunk, any> ? TChunk : never;

/**
 * Client callbacks for stream consumption
 */
export type RiverStreamCallbacks<TChunk> = {
  onStart?: (data: { streamRunId: string; encodedResumptionToken: string }) => void;
  onChunk?: (chunk: TChunk) => void;
  onSuccess?: (data: { totalChunks: number; totalTimeMs: number }) => void;
  onError?: (error: RiverError) => void;
  onFatalError?: (error: RiverError) => void;
  onInfo?: (data: { encodedResumptionToken: string }) => void;
  onAbort?: () => void;
};

/**
 * Stream caller (client-side)
 */
export type RiverStreamCaller<TInput, _TChunk> = {
  start: (input: TInput) => void;
  resume: (resumeKey: string) => void;
  abort: () => void;
};
