/**
 * River Next.js Server Adapter
 *
 * Route handler for App Router (GET/POST endpoints)
 */

import { NextRequest, NextResponse } from "next/server";
import type { RiverRouter } from "./types";
import { decodeResumptionToken } from "./resumeToken";
import { streamToSSE } from "./helpers";

/**
 * Create River endpoint handlers for Next.js App Router
 *
 * @example
 * ```ts
 * // app/api/chat/route.ts
 * const { GET, POST } = riverEndpointHandler(myRouter);
 * export { GET, POST };
 * ```
 */
export function riverEndpointHandler<T extends RiverRouter>(router: T) {
  /**
   * POST: Start new stream
   * Body: { routerStreamKey: string, input: unknown }
   */
  async function POST(request: NextRequest) {
    try {
      const body = await request.json();
      const { routerStreamKey, input } = body;

      // Validate router stream key
      const streamDef = router[routerStreamKey];
      if (!streamDef) {
        return NextResponse.json(
          { error: "Stream not found" },
          { status: 404 }
        );
      }

      // Validate input with Zod schema
      const parseResult = streamDef.inputSchema.safeParse(input);
      if (!parseResult.success) {
        return NextResponse.json(
          {
            error: "Invalid input",
            details: parseResult.error.issues,
          },
          { status: 400 }
        );
      }

      // Create abort controller
      const abortController = new AbortController();

      // Listen for client disconnect
      request.signal.addEventListener("abort", () => {
        abortController.abort();
      });

      // Start stream via provider
      const stream = streamDef.provider.startStream(
        parseResult.data,
        request,
        streamDef.runner,
        abortController
      );

      // Convert to SSE format
      const sseStream = streamToSSE(stream);

      // Return streaming response
      return new NextResponse(sseStream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache, no-transform",
          Connection: "keep-alive",
        },
      });
    } catch (error) {
      console.error("River POST error:", error);
      return NextResponse.json(
        {
          error:
            error instanceof Error ? error.message : "Internal server error",
        },
        { status: 500 }
      );
    }
  }

  /**
   * GET: Resume stream
   * Query: ?resumeKey=<base64 token>&lastId=<redis stream id>
   */
  async function GET(request: NextRequest) {
    try {
      const searchParams = request.nextUrl.searchParams;
      const resumeKey = searchParams.get("resumeKey");
      const lastId = searchParams.get("lastId") || "0-0";

      if (!resumeKey) {
        return NextResponse.json(
          { error: "resumeKey parameter required" },
          { status: 400 }
        );
      }

      // Decode resumption token
      const tokenResult = decodeResumptionToken(resumeKey);
      if (tokenResult.isErr()) {
        return NextResponse.json(
          { error: "Invalid resumption token" },
          { status: 400 }
        );
      }

      const token = tokenResult.value;
      const { routerStreamKey } = token;

      // Get stream definition
      const streamDef = router[routerStreamKey];
      if (!streamDef) {
        return NextResponse.json(
          { error: "Stream not found" },
          { status: 404 }
        );
      }

      // Check if provider supports resume
      if (!streamDef.provider.isResumable || !streamDef.provider.resumeStream) {
        return NextResponse.json(
          { error: "Provider does not support resumption" },
          { status: 400 }
        );
      }

      // Resume stream
      const streamResult = streamDef.provider.resumeStream(token, lastId);
      if (streamResult.isErr()) {
        return NextResponse.json(
          { error: streamResult.error.message },
          { status: 500 }
        );
      }

      const stream = streamResult.value;

      // Convert to SSE format
      const sseStream = streamToSSE(stream);

      // Return streaming response
      return new NextResponse(sseStream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache, no-transform",
          Connection: "keep-alive",
        },
      });
    } catch (error) {
      console.error("River GET error:", error);
      return NextResponse.json(
        {
          error:
            error instanceof Error ? error.message : "Internal server error",
        },
        { status: 500 }
      );
    }
  }

  return { GET, POST };
}
