/**
 * River Helper Utilities
 *
 * Utility functions for working with streams and async iteration
 */

import type { RiverStreamItem } from "./types";

/**
 * Create an AsyncIterable from a ReadableStream
 * Allows using `for await` loops with ReadableStream
 */
export function createAsyncIterableStream<T>(
  stream: ReadableStream<T>
): ReadableStream<T> & AsyncIterable<T> {
  const reader = stream.getReader();

  const asyncIterable: AsyncIterable<T> = {
    [Symbol.asyncIterator](): AsyncIterator<T> {
      return {
        async next(): Promise<IteratorResult<T>> {
          const { done, value } = await reader.read();
          if (done) {
            return { done: true, value: undefined };
          }
          return { done: false, value };
        },
        async return(): Promise<IteratorResult<T>> {
          await reader.cancel();
          return { done: true, value: undefined };
        },
      };
    },
  };

  return Object.assign(stream, asyncIterable);
}

/**
 * Convert ReadableStream to SSE (Server-Sent Events) format
 */
export function streamToSSE<TChunk>(
  stream: ReadableStream<RiverStreamItem<TChunk>>
): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();

  return stream.pipeThrough(
    new TransformStream<RiverStreamItem<TChunk>, Uint8Array>({
      transform(item, controller) {
        const data = JSON.stringify(item);
        const sseMessage = `data: ${data}\n\n`;
        controller.enqueue(encoder.encode(sseMessage));
      },
    })
  );
}

/**
 * Parse SSE message to RiverStreamItem
 */
export function parseSSEMessage<TChunk>(
  message: string
): RiverStreamItem<TChunk> | null {
  try {
    // SSE messages are formatted as "data: {json}\n\n"
    const dataPrefix = "data: ";
    if (!message.startsWith(dataPrefix)) {
      return null;
    }

    const jsonStr = message.slice(dataPrefix.length).trim();
    if (!jsonStr) {
      return null;
    }

    return JSON.parse(jsonStr) as RiverStreamItem<TChunk>;
  } catch {
    return null;
  }
}

/**
 * Generate a unique stream run ID
 */
export function generateStreamRunId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

/**
 * Sleep utility for testing/delays
 */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
