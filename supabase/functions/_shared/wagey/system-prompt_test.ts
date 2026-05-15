import { assert, assertStringIncludes } from "jsr:@std/assert";

import { getSystemPrompt, WAGEY_MESSAGE_BREAK_TOKEN } from "./system-prompt.ts";

Deno.test("getSystemPrompt prefers explicit bubble breaks when supported", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
    allowMessageBreaks: true,
  });

  assertStringIncludes(prompt, "<message_bubbles>");
  assertStringIncludes(prompt, WAGEY_MESSAGE_BREAK_TOKEN);
  assertStringIncludes(
    prompt,
    "Prefer starting a new bubble instead of using plain newline-separated paragraphs",
  );
  assertStringIncludes(
    prompt,
    "split short conversational segments into separate bubbles",
  );
});

Deno.test("getSystemPrompt omits bubble instructions for legacy clients", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
    allowMessageBreaks: false,
  });

  assert(!prompt.includes("<message_bubbles>"));
});

Deno.test("getSystemPrompt includes simple agent operating model", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
  });

  assertStringIncludes(prompt, "<agent_operating_model>");
  assertStringIncludes(prompt, "Use the simplest reliable path");
  assertStringIncludes(prompt, "observe -> act -> verify loop");
  assertStringIncludes(prompt, "If tool output contradicts your assumption");
});
