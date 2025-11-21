/**
 * Redis Provider for River
 *
 * Enables resumable/durable streams using Redis Streams
 * Stores chunks in Redis so users can resume after page reload
 */

import Redis from "ioredis";
import type {
  RiverProvider,
  RiverRunnerFn,
  RiverStreamItem,
  RiverStreamMethods,
  ResumptionTokenData,
} from "./types";
import { RiverError } from "./types";
import { generateStreamRunId } from "./helpers";
import { encodeResumptionToken } from "./resumeToken";
import { ok, err, Result } from "neverthrow";

/**
 * Redis provider configuration
 */
export type RedisProviderConfig = {
  redisClient: Redis;
  streamStorageId: string;
  waitUntil?: (promise: Promise<void>) => void;
};

/**
 * Special marker for end of stream in Redis
 */
const STREAM_END_MARKER = "STREAM_END" as const;

/**
 * Max read attempts before considering stream ended
 */
const MAX_READ_ATTEMPTS = 1000;

/**
 * Blocking read timeout in milliseconds
 */
const BLOCK_TIMEOUT_MS = 10;

/**
 * Create Redis provider for resumable streams
 */
export function redisProvider(config: RedisProviderConfig): RiverProvider {
  const { redisClient, streamStorageId, waitUntil } = config;

  return {
    isResumable: true,
    providerId: "redis",

    startStream: <TInput, TChunk, TAdapterRequest>(
      input: TInput,
      adapterRequest: TAdapterRequest,
      runnerFn: RiverRunnerFn<TInput, TChunk, TAdapterRequest>,
      abortController: AbortController
    ): ReadableStream<RiverStreamItem<TChunk>> => {
      const streamRunId = generateStreamRunId();
      const redisKey = `stream-${streamStorageId}-${streamRunId}`;
      const startTime = Date.now();
      let chunkCount = 0;

      // Background execution promise
      const executionPromise = (async () => {
        const stream: RiverStreamMethods<TChunk> = {
          appendChunk: async (chunk: TChunk) => {
            if (abortController.signal.aborted) return;

            chunkCount++;
            const item: RiverStreamItem<TChunk> = { type: "chunk", chunk };
            await redisClient.xadd(
              redisKey,
              "*",
              "item",
              JSON.stringify(item)
            );
          },

          appendError: async (error: RiverError) => {
            if (abortController.signal.aborted) return;

            const item: RiverStreamItem<TChunk> = {
              type: "special",
              special: {
                RIVER_SPECIAL_TYPE_KEY: "stream_error",
                error: error.toJSON(),
              },
            };
            await redisClient.xadd(
              redisKey,
              "*",
              "item",
              JSON.stringify(item)
            );
          },

          sendFatalErrorAndClose: async (error: RiverError) => {
            const item: RiverStreamItem<TChunk> = {
              type: "special",
              special: {
                RIVER_SPECIAL_TYPE_KEY: "stream_fatal_error",
                error: error.toJSON(),
              },
            };
            await redisClient.xadd(
              redisKey,
              "*",
              "item",
              JSON.stringify(item)
            );
            await redisClient.xadd(redisKey, "*", "end", STREAM_END_MARKER);
          },

          close: async () => {
            const totalTimeMs = Date.now() - startTime;
            const item: RiverStreamItem<TChunk> = {
              type: "special",
              special: {
                RIVER_SPECIAL_TYPE_KEY: "stream_end",
                totalChunks: chunkCount,
                totalTimeMs,
              },
            };
            await redisClient.xadd(
              redisKey,
              "*",
              "item",
              JSON.stringify(item)
            );
            await redisClient.xadd(redisKey, "*", "end", STREAM_END_MARKER);
          },
        };

        try {
          await runnerFn({
            input,
            stream,
            abortSignal: abortController.signal,
            adapterRequest,
          });
        } catch (error) {
          await stream.sendFatalErrorAndClose(
            new RiverError(
              error instanceof Error ? error.message : "Unknown error",
              "stream",
              { cause: error }
            )
          );
        }
      })();

      // Use waitUntil if provided (Vercel/Cloudflare Workers)
      if (waitUntil) {
        waitUntil(executionPromise);
      }

      // Return readable stream that reads from Redis
      return new ReadableStream<RiverStreamItem<TChunk>>({
        async start(controller) {
          // Send stream_start immediately
          const resumptionToken: ResumptionTokenData = {
            providerId: "redis",
            routerStreamKey: "unknown", // Will be set by endpoint handler
            streamStorageId,
            streamRunId,
          };

          controller.enqueue({
            type: "special",
            special: {
              RIVER_SPECIAL_TYPE_KEY: "stream_start",
              streamRunId,
              encodedResumptionToken: encodeResumptionToken(resumptionToken),
            },
          });

          let lastId = "0-0";
          let attempts = 0;

          // Read from Redis Stream with blocking reads
          while (attempts < MAX_READ_ATTEMPTS) {
            if (abortController.signal.aborted) {
              controller.enqueue({ type: "aborted" });
              controller.close();
              return;
            }

            try {
              const results = await redisClient.xread(
                "BLOCK",
                BLOCK_TIMEOUT_MS,
                "STREAMS",
                redisKey,
                lastId
              );

              if (!results || results.length === 0) {
                attempts++;
                continue;
              }

              const [, messages] = results[0];

              for (const [id, fields] of messages) {
                lastId = id;

                // Check for end marker
                if (fields[0] === "end" && fields[1] === STREAM_END_MARKER) {
                  controller.close();
                  return;
                }

                // Parse and enqueue item
                if (fields[0] === "item") {
                  const item = JSON.parse(fields[1]) as RiverStreamItem<TChunk>;
                  controller.enqueue(item);

                  // Close on fatal error
                  if (
                    item.type === "special" &&
                    item.special.RIVER_SPECIAL_TYPE_KEY === "stream_fatal_error"
                  ) {
                    controller.close();
                    return;
                  }

                  // Close on stream_end
                  if (
                    item.type === "special" &&
                    item.special.RIVER_SPECIAL_TYPE_KEY === "stream_end"
                  ) {
                    controller.close();
                    return;
                  }
                }
              }

              // Reset attempts on successful read
              attempts = 0;
            } catch (error) {
              console.error("Redis read error:", error);
              attempts++;
            }
          }

          // Timeout after max attempts
          controller.close();
        },

        cancel() {
          abortController.abort();
        },
      });
    },

    resumeStream: <TChunk>(
      resumptionToken: ResumptionTokenData,
      lastId: string = "0-0"
    ): Result<ReadableStream<RiverStreamItem<TChunk>>, RiverError> => {
      const { streamStorageId: tokenStorageId, streamRunId } = resumptionToken;

      // Validate storage ID matches
      if (tokenStorageId !== streamStorageId) {
        return err(
          new RiverError(
            "Storage ID mismatch",
            "storage",
            { expected: streamStorageId, got: tokenStorageId }
          )
        );
      }

      const redisKey = `stream-${streamStorageId}-${streamRunId}`;
      const abortController = new AbortController();

      const stream = new ReadableStream<RiverStreamItem<TChunk>>({
        async start(controller) {
          let currentId = lastId;
          let attempts = 0;

          // Read from Redis Stream starting from lastId
          while (attempts < MAX_READ_ATTEMPTS) {
            if (abortController.signal.aborted) {
              controller.enqueue({ type: "aborted" });
              controller.close();
              return;
            }

            try {
              const results = await redisClient.xread(
                "BLOCK",
                BLOCK_TIMEOUT_MS,
                "STREAMS",
                redisKey,
                currentId
              );

              if (!results || results.length === 0) {
                attempts++;
                continue;
              }

              const [, messages] = results[0];

              for (const [id, fields] of messages) {
                currentId = id;

                // Check for end marker
                if (fields[0] === "end" && fields[1] === STREAM_END_MARKER) {
                  controller.close();
                  return;
                }

                // Parse and enqueue item
                if (fields[0] === "item") {
                  const item = JSON.parse(fields[1]) as RiverStreamItem<TChunk>;
                  controller.enqueue(item);

                  // Close on fatal error or stream_end
                  if (
                    item.type === "special" &&
                    (item.special.RIVER_SPECIAL_TYPE_KEY === "stream_fatal_error" ||
                      item.special.RIVER_SPECIAL_TYPE_KEY === "stream_end")
                  ) {
                    controller.close();
                    return;
                  }
                }
              }

              attempts = 0;
            } catch (error) {
              console.error("Redis resume read error:", error);
              attempts++;
            }
          }

          controller.close();
        },

        cancel() {
          abortController.abort();
        },
      });

      return ok(stream);
    },
  };
}
