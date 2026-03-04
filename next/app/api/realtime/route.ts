import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { Effect } from "effect";
import { getSession } from "@/data-access/auth";
import { OpenAIRealtimeService, type RealtimeEvent } from "@/lib/services/openai-realtime";
import { OpenAIRealtimeLive } from "@/lib/layers/app";

const realtimeRequestSchema = z.object({
  model: z.string().min(1).optional(),
  instructions: z.string().min(1).optional(),
  events: z.array(z.record(z.string(), z.unknown())).optional(),
  timeoutMs: z.number().int().min(1000).max(120_000).optional(),
  autoCloseOnResponseDone: z.boolean().optional(),
});

type RealtimeRequestBody = z.infer<typeof realtimeRequestSchema>;

function formatSseData(data: unknown): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(data)}\n\n`);
}

function extractErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return "Realtime session failed";
}

/**
 * POST /api/realtime
 *
 * Starts a server-side OpenAI Realtime WebSocket session and forwards
 * server events to the client as SSE.
 */
export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let parsedBody: RealtimeRequestBody;
  try {
    const json = await request.json();
    parsedBody = realtimeRequestSchema.parse(json);
  } catch {
    return NextResponse.json(
      { error: "Invalid request body" },
      { status: 400 }
    );
  }

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: unknown) => {
        try {
          controller.enqueue(formatSseData(event));
        } catch {
          // Stream already closed by client
        }
      };

      try {
        const program = Effect.gen(function* () {
          const realtime = yield* OpenAIRealtimeService;
          return yield* realtime.streamSession({
            model: parsedBody.model,
            instructions: parsedBody.instructions,
            events: (parsedBody.events ?? []) as RealtimeEvent[],
            timeoutMs: parsedBody.timeoutMs,
            signal: request.signal,
            autoCloseOnResponseDone: parsedBody.autoCloseOnResponseDone,
            onEvent: (event) => {
              send(event);
            },
          });
        }).pipe(Effect.provide(OpenAIRealtimeLive), Effect.scoped);

        await Effect.runPromise(program);
      } catch (error) {
        send({
          type: "error",
          message: extractErrorMessage(error),
        });
      } finally {
        send({ type: "done" });
        try {
          controller.enqueue(new TextEncoder().encode("data: [DONE]\n\n"));
        } catch {
          // Stream already closed by client
        }
        controller.close();
      }
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-store, must-revalidate",
      Connection: "keep-alive",
    },
  });
}
