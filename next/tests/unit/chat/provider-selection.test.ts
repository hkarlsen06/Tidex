import { describe, expect, it, vi, beforeEach } from "vitest";
import { Effect } from "effect";
import type { StreamChunk } from "@/lib/services/claude";

const mocks = vi.hoisted(() => ({
  claudeStreamChat: vi.fn(),
  openaiStreamChat: vi.fn(),
}));

vi.mock("@/lib/chat/executor", () => ({
  executeTool: vi.fn(),
}));

vi.mock("@/lib/layers/app", async () => {
  const { Layer } = await import("effect");
  const { ClaudeService } = await import("@/lib/services/claude");
  const { OpenAIService } = await import("@/lib/services/openai");

  return {
    ClaudeLive: Layer.succeed(ClaudeService, {
      streamChat: mocks.claudeStreamChat,
    }),
    OpenAILive: Layer.succeed(OpenAIService, {
      streamChat: mocks.openaiStreamChat,
    }),
  };
});

function createStream(chunks: StreamChunk[]): AsyncIterable<StreamChunk> {
  return {
    async *[Symbol.asyncIterator]() {
      for (const chunk of chunks) {
        yield chunk;
      }
    },
  };
}

describe("chat router provider selection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("uses Claude service when provider is claude", async () => {
    mocks.claudeStreamChat.mockReturnValue(
      Effect.succeed(
        createStream([
          { type: "text", content: "Hei" },
          { type: "done", stopReason: "stop" },
        ])
      )
    );

    const { streamChatWithProvider } = await import("@/lib/chat/router");
    const stream = await streamChatWithProvider("claude", {
      system: "You are Wagey",
      messages: [{ role: "user", content: "Hello" }],
    });

    const chunkTypes: string[] = [];
    for await (const chunk of stream) {
      chunkTypes.push(chunk.type);
    }

    expect(mocks.claudeStreamChat).toHaveBeenCalledTimes(1);
    expect(mocks.openaiStreamChat).not.toHaveBeenCalled();
    expect(chunkTypes).toEqual(["text", "done"]);
  });

  it("uses OpenAI service when provider is chatgpt", async () => {
    mocks.openaiStreamChat.mockReturnValue(
      Effect.succeed(
        createStream([
          { type: "text", content: "Hi" },
          {
            type: "tool_use",
            id: "call_1",
            name: "manage_shift",
            input: { action: "create" },
          },
          { type: "done", stopReason: "completed" },
        ])
      )
    );

    const { streamChatWithProvider } = await import("@/lib/chat/router");
    const stream = await streamChatWithProvider("chatgpt", {
      system: "You are Wagey",
      messages: [{ role: "user", content: "Create shift" }],
    });

    const chunkTypes: string[] = [];
    for await (const chunk of stream) {
      chunkTypes.push(chunk.type);
    }

    expect(mocks.openaiStreamChat).toHaveBeenCalledTimes(1);
    expect(mocks.claudeStreamChat).not.toHaveBeenCalled();
    expect(chunkTypes).toEqual(["text", "tool_use", "done"]);
  });
});
