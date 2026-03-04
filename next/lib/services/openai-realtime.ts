/**
 * OpenAI Realtime WebSocket Service
 *
 * Server-to-server WebSocket integration for OpenAI Realtime API.
 */

import "server-only";

import WebSocket from "ws";
import { Context, Effect, Layer, Redacted } from "effect";
import { AIError } from "@/lib/errors/tagged";
import { AppConfig } from "./config";

const OPENAI_REALTIME_WS_URL = "wss://api.openai.com/v1/realtime";

const DEFAULT_TIMEOUT_MS = 30_000;

export type RealtimeEvent = {
  type: string;
  [key: string]: unknown;
};

export type RealtimeSessionOptions = {
  model?: string;
  instructions?: string;
  events?: RealtimeEvent[];
  timeoutMs?: number;
  signal?: AbortSignal;
  onEvent: (event: RealtimeEvent) => void;
  autoCloseOnResponseDone?: boolean;
};

export class OpenAIRealtimeService extends Context.Tag("OpenAIRealtimeService")<
  OpenAIRealtimeService,
  {
    readonly streamSession: (
      options: RealtimeSessionOptions
    ) => Effect.Effect<void, AIError, never>;
  }
>() {}

function parseRealtimeEvent(rawData: WebSocket.RawData): RealtimeEvent | null {
  const payload = typeof rawData === "string" ? rawData : rawData.toString();
  try {
    return JSON.parse(payload) as RealtimeEvent;
  } catch {
    return null;
  }
}

function toAIError(message: string, cause?: unknown): AIError {
  return new AIError({
    provider: "openai",
    operation: "realtime_websocket",
    message,
    cause,
  });
}

export const OpenAIRealtimeServiceLive = Layer.effect(
  OpenAIRealtimeService,
  Effect.gen(function* () {
    const config = yield* AppConfig;
    const apiKey = Redacted.value(config.ai.openaiApiKey);
    const defaultModel = config.ai.openaiRealtimeModel;

    const streamSession = (
      options: RealtimeSessionOptions
    ): Effect.Effect<void, AIError, never> =>
      Effect.async((resume) => {
        if (options.signal?.aborted) {
          resume(Effect.fail(toAIError("Request aborted before socket open")));
          return;
        }

        const model = options.model ?? defaultModel;
        const timeoutMs = Math.max(1_000, options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
        const autoCloseOnResponseDone = options.autoCloseOnResponseDone ?? true;
        const url = `${OPENAI_REALTIME_WS_URL}?model=${encodeURIComponent(model)}`;

        const ws = new WebSocket(url, {
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
        });

        let settled = false;
        let timedOut = false;
        let aborted = false;
        let timeoutHandle: ReturnType<typeof setTimeout> | null = null;

        const complete = (effect: Effect.Effect<void, AIError, never>) => {
          if (settled) return;
          settled = true;
          if (timeoutHandle) {
            clearTimeout(timeoutHandle);
            timeoutHandle = null;
          }
          if (options.signal) {
            options.signal.removeEventListener("abort", onAbort);
          }
          resume(effect);
        };

        const closeSocket = (code = 1000, reason?: string) => {
          if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
            ws.close(code, reason);
          }
        };

        const onAbort = () => {
          aborted = true;
          closeSocket(1000, "client_aborted");
        };

        if (options.signal) {
          options.signal.addEventListener("abort", onAbort);
        }

        timeoutHandle = setTimeout(() => {
          timedOut = true;
          closeSocket(1000, "session_timeout");
        }, timeoutMs);

        ws.on("open", () => {
          if (options.instructions) {
            ws.send(
              JSON.stringify({
                type: "session.update",
                session: {
                  type: "realtime",
                  instructions: options.instructions,
                },
              })
            );
          }

          for (const event of options.events ?? []) {
            ws.send(JSON.stringify(event));
          }
        });

        ws.on("message", (data) => {
          const event = parseRealtimeEvent(data);
          if (!event) return;

          try {
            options.onEvent(event);
          } catch (error) {
            complete(Effect.fail(toAIError("Realtime event handler failed", error)));
            closeSocket(1011, "event_handler_failed");
            return;
          }

          if (autoCloseOnResponseDone && event.type === "response.done") {
            closeSocket(1000, "response_done");
          }
        });

        ws.on("error", (error) => {
          complete(Effect.fail(toAIError("Realtime websocket error", error)));
        });

        ws.on("close", (code, reason) => {
          if (timedOut) {
            complete(
              Effect.fail(
                toAIError(`Realtime session timed out after ${timeoutMs}ms`)
              )
            );
            return;
          }
          if (aborted) {
            complete(Effect.fail(toAIError("Realtime session aborted")));
            return;
          }

          if (code !== 1000) {
            const reasonText = reason.toString();
            const reasonSuffix = reasonText ? ` (${reasonText})` : "";
            complete(
              Effect.fail(
                toAIError(
                  `Realtime websocket closed unexpectedly with code ${code}${reasonSuffix}`
                )
              )
            );
            return;
          }

          complete(Effect.succeed(undefined));
        });
      });

    return {
      streamSession,
    };
  })
);
