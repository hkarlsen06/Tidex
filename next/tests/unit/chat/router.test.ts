import { describe, expect, it } from "vitest";
import { convertToOpenAIMessages } from "@/lib/chat/router";
import { toOpenAIInput } from "@/lib/services/openai";

describe("chat router message mapping", () => {
  it("maps text, images, tool calls, tool results, and legacy compaction", () => {
    const { system, messages } = convertToOpenAIMessages(
      [
        {
          role: "system",
          content: "System instructions",
        },
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: "image/jpeg",
                data: "abc123",
              },
            },
            {
              type: "text",
              text: "What shift is this?",
            },
          ],
        },
        {
          role: "assistant",
          content: "Looking it up",
          tool_calls: [
            {
              id: "call_1",
              type: "function",
              function: {
                name: "query_shifts",
                arguments: "{\"limit\":1}",
              },
            },
          ],
        },
        {
          role: "tool",
          content: "{\"success\":true}",
          tool_call_id: "call_1",
        },
      ],
      "<summary>Older context</summary>"
    );

    expect(system).toBe("System instructions");
    expect(messages).toHaveLength(4);

    const input = toOpenAIInput(messages);
    expect(input[0]).toEqual({
      role: "assistant",
      content: [
        {
          type: "output_text",
          text: "<summary>Older context</summary>",
        },
      ],
    });
    expect(input[1]).toEqual({
      role: "user",
      content: [
        {
          type: "input_image",
          image_url: "data:image/jpeg;base64,abc123",
        },
        {
          type: "input_text",
          text: "What shift is this?",
        },
      ],
    });
    expect(input[2]).toEqual({
      role: "assistant",
      content: [
        {
          type: "output_text",
          text: "Looking it up",
        },
      ],
    });
    expect(input[3]).toEqual({
      type: "function_call",
      call_id: "call_1",
      name: "query_shifts",
      arguments: "{\"limit\":1}",
    });
    expect(input[4]).toEqual({
      type: "function_call_output",
      call_id: "call_1",
      output: "{\"success\":true}",
    });
  });
});
