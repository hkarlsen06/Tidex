/**
 * Default River Provider (In-Memory)
 *
 * Simple in-memory provider for non-resumable streams
 * Good for development and simple use cases
 */

import type {
  RiverProvider,
  RiverRunnerFn,
  RiverStreamItem,
  RiverStreamMethods,
} from "./types";
import { RiverError } from "./types";
import { generateStreamRunId } from "./helpers";
import { encodeResumptionToken } from "./resumeToken";

/**
 * Create default (in-memory) provider
 */
export function defaultRiverProvider(): RiverProvider {
  return {
    isResumable: false,
    providerId: "default",

    startStream: <TInput, TChunk, TAdapterRequest>(
      input: TInput,
      _adapterRequest: TAdapterRequest,
      runnerFn: RiverRunnerFn<TInput, TChunk, TAdapterRequest>,
      abortController: AbortController
    ): ReadableStream<RiverStreamItem<TChunk>> => {
      const streamRunId = generateStreamRunId();
      const startTime = Date.now();
      let chunkCount = 0;

      return new ReadableStream<RiverStreamItem<TChunk>>({
        async start(controller) {
          // Send stream_start special chunk
          const encodedToken = encodeResumptionToken({
            providerId: "default",
            routerStreamKey: "unknown",
            streamStorageId: "default",
            streamRunId,
          });

          controller.enqueue({
            type: "special",
            special: {
              RIVER_SPECIAL_TYPE_KEY: "stream_start",
              streamRunId,
              encodedResumptionToken: encodedToken,
            },
          });

          // Create stream methods
          const stream: RiverStreamMethods<TChunk> = {
            appendChunk: async (chunk: TChunk) => {
              if (abortController.signal.aborted) {
                return;
              }
              chunkCount++;
              controller.enqueue({ type: "chunk", chunk });
            },

            appendError: async (error: RiverError) => {
              if (abortController.signal.aborted) {
                return;
              }
              controller.enqueue({
                type: "special",
                special: {
                  RIVER_SPECIAL_TYPE_KEY: "stream_error",
                  error: error.toJSON(),
                },
              });
            },

            sendFatalErrorAndClose: async (error: RiverError) => {
              controller.enqueue({
                type: "special",
                special: {
                  RIVER_SPECIAL_TYPE_KEY: "stream_fatal_error",
                  error: error.toJSON(),
                },
              });
              controller.close();
            },

            close: async () => {
              const totalTimeMs = Date.now() - startTime;
              controller.enqueue({
                type: "special",
                special: {
                  RIVER_SPECIAL_TYPE_KEY: "stream_end",
                  totalChunks: chunkCount,
                  totalTimeMs,
                },
              });
              controller.close();
            },
          };

          // Run the user's stream logic
          try {
            await runnerFn({
              input,
              stream,
              abortSignal: abortController.signal,
              adapterRequest: _adapterRequest,
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
        },

        cancel() {
          abortController.abort();
        },
      });
    },
  };
}
