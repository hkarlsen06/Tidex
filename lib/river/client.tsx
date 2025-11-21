/**
 * River React Client
 *
 * React hooks for consuming River streams with type safety
 */

"use client";

import { useCallback, useRef } from "react";
import type {
  RiverRouter,
  RiverStreamCallbacks,
  RiverStreamCaller,
  InferRiverStreamInputType,
  InferRiverStreamChunkType,
  RiverStreamItem,
} from "./types";
import { RiverError, RIVER_SPECIAL_TYPE_KEY } from "./types";
import { parseSSEMessage } from "./helpers";

/**
 * Create River client for consuming streams
 *
 * @example
 * ```tsx
 * const client = createRiverClient<typeof myRouter>('/api/chat');
 * const chatCaller = client.chat.useStream({
 *   onChunk: (chunk) => console.log(chunk),
 * });
 * chatCaller.start({ prompt: "Hello" });
 * ```
 */
export function createRiverClient<T extends RiverRouter>(endpoint: string) {
  type ClientType = {
    [K in keyof T]: {
      useStream: (
        callbacks: RiverStreamCallbacks<InferRiverStreamChunkType<T[K]>>
      ) => RiverStreamCaller<
        InferRiverStreamInputType<T[K]>,
        InferRiverStreamChunkType<T[K]>
      >;
    };
  };

  const proxy = new Proxy({} as ClientType, {
    get(_target, routerStreamKey: string) {
      return {
        useStream: (
          callbacks: RiverStreamCallbacks<any>
        ): RiverStreamCaller<any, any> => {
          return useRiverStream(endpoint, routerStreamKey, callbacks);
        },
      };
    },
  });

  return proxy;
}

/**
 * Internal hook for stream consumption
 */
function useRiverStream<TInput, TChunk>(
  endpoint: string,
  routerStreamKey: string,
  callbacks: RiverStreamCallbacks<TChunk>
): RiverStreamCaller<TInput, TChunk> {
  const abortControllerRef = useRef<AbortController | null>(null);
  const eventSourceRef = useRef<EventSource | null>(null);

  /**
   * Cleanup active connections
   */
  const cleanup = useCallback(() => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      eventSourceRef.current = null;
    }
  }, []);

  /**
   * Process incoming stream item
   */
  const processItem = useCallback(
    (item: RiverStreamItem<TChunk>) => {
      if (item.type === "chunk") {
        callbacks.onChunk?.(item.chunk);
      } else if (item.type === "special") {
        const specialType = item.special[RIVER_SPECIAL_TYPE_KEY];

        switch (specialType) {
          case "stream_start":
            callbacks.onStart?.({
              streamRunId: item.special.streamRunId,
              encodedResumptionToken: item.special.encodedResumptionToken,
            });
            callbacks.onInfo?.({
              encodedResumptionToken: item.special.encodedResumptionToken,
            });
            break;

          case "stream_end":
            callbacks.onSuccess?.({
              totalChunks: item.special.totalChunks,
              totalTimeMs: item.special.totalTimeMs,
            });
            cleanup();
            break;

          case "stream_error":
            callbacks.onError?.(RiverError.fromJSON(item.special.error));
            break;

          case "stream_fatal_error":
            callbacks.onFatalError?.(RiverError.fromJSON(item.special.error));
            cleanup();
            break;
        }
      } else if (item.type === "aborted") {
        callbacks.onAbort?.();
        cleanup();
      }
    },
    [callbacks, cleanup]
  );

  /**
   * Start a new stream
   */
  const start = useCallback(
    async (input: TInput) => {
      // Cleanup any previous stream
      cleanup();

      // Create new abort controller
      const abortController = new AbortController();
      abortControllerRef.current = abortController;

      try {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            routerStreamKey,
            input,
          }),
          signal: abortController.signal,
        });

        if (!response.ok) {
          const errorData = await response.json();
          callbacks.onFatalError?.(
            new RiverError(
              errorData.error || "Stream start failed",
              "network"
            )
          );
          return;
        }

        if (!response.body) {
          callbacks.onFatalError?.(
            new RiverError("No response body", "network")
          );
          return;
        }

        // Read SSE stream
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (true) {
          const { done, value } = await reader.read();

          if (done) {
            break;
          }

          // Decode and append to buffer
          buffer += decoder.decode(value, { stream: true });

          // Process complete SSE messages
          const messages = buffer.split("\n\n");
          buffer = messages.pop() || ""; // Keep incomplete message in buffer

          for (const message of messages) {
            if (!message.trim()) continue;

            const item = parseSSEMessage<TChunk>(message);
            if (item) {
              processItem(item);
            }
          }
        }
      } catch (error) {
        if (error instanceof Error && error.name === "AbortError") {
          callbacks.onAbort?.();
        } else {
          callbacks.onFatalError?.(
            new RiverError(
              error instanceof Error ? error.message : "Stream failed",
              "network",
              { cause: error }
            )
          );
        }
      } finally {
        cleanup();
      }
    },
    [endpoint, routerStreamKey, callbacks, cleanup, processItem]
  );

  /**
   * Resume an existing stream
   */
  const resume = useCallback(
    async (resumeKey: string, lastId: string = "0-0") => {
      // Cleanup any previous stream
      cleanup();

      // Create new abort controller
      const abortController = new AbortController();
      abortControllerRef.current = abortController;

      try {
        const url = `${endpoint}?resumeKey=${encodeURIComponent(
          resumeKey
        )}&lastId=${encodeURIComponent(lastId)}`;

        const response = await fetch(url, {
          method: "GET",
          signal: abortController.signal,
        });

        if (!response.ok) {
          const errorData = await response.json();
          callbacks.onFatalError?.(
            new RiverError(
              errorData.error || "Stream resume failed",
              "network"
            )
          );
          return;
        }

        if (!response.body) {
          callbacks.onFatalError?.(
            new RiverError("No response body", "network")
          );
          return;
        }

        // Read SSE stream
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (true) {
          const { done, value } = await reader.read();

          if (done) {
            break;
          }

          buffer += decoder.decode(value, { stream: true });

          const messages = buffer.split("\n\n");
          buffer = messages.pop() || "";

          for (const message of messages) {
            if (!message.trim()) continue;

            const item = parseSSEMessage<TChunk>(message);
            if (item) {
              processItem(item);
            }
          }
        }
      } catch (error) {
        if (error instanceof Error && error.name === "AbortError") {
          callbacks.onAbort?.();
        } else {
          callbacks.onFatalError?.(
            new RiverError(
              error instanceof Error ? error.message : "Stream resume failed",
              "network",
              { cause: error }
            )
          );
        }
      } finally {
        cleanup();
      }
    },
    [endpoint, callbacks, cleanup, processItem]
  );

  /**
   * Abort the current stream
   */
  const abort = useCallback(() => {
    cleanup();
    callbacks.onAbort?.();
  }, [cleanup, callbacks]);

  return {
    start,
    resume,
    abort,
  };
}
