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

Deno.test("getSystemPrompt includes supported deeplink instructions", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
    deeplinks: [
      {
        destination: "settings.pay",
        url: "tidex://settings/pay?jobId=JOB_ID",
        parameters: ["jobId"],
      },
      {
        destination: "shifts",
        url: "tidex://shifts",
      },
      {
        destination: "shifts.shift",
        url:
          "tidex://shifts?dates=YYYY-MM-DD&shiftIds=SHIFT_ID&action=highlight",
        parameters: ["dates", "shiftIds", "action"],
      },
      {
        destination: "add_shift.recurring",
        url: "tidex://add-shift?mode=recurring",
        parameters: ["mode"],
      },
      {
        destination: "settings.recurring_shifts",
        url: "tidex://settings/recurring-shifts",
      },
      {
        destination: "sharing.manage",
        url: "tidex://sharing/manage?highlight=USER_ID",
        parameters: ["highlight"],
      },
      {
        destination: "admin.report",
        url: "tidex://admin?tab=reports&reportId=REPORT_ID",
        parameters: ["tab", "reportId"],
      },
    ],
  });

  assertStringIncludes(prompt, "<deeplinks>");
  assertStringIncludes(
    prompt,
    "settings.pay: tidex://settings/pay?jobId=JOB_ID",
  );
  assertStringIncludes(prompt, "shifts: tidex://shifts");
  assertStringIncludes(
    prompt,
    "add_shift.recurring: tidex://add-shift?mode=recurring",
  );
  assertStringIncludes(
    prompt,
    "sharing.manage: tidex://sharing/manage?highlight=USER_ID",
  );
  assertStringIncludes(
    prompt,
    "admin.report: tidex://admin?tab=reports&reportId=REPORT_ID",
  );
  assertStringIncludes(
    prompt,
    "Use add_shift.single for ordinary shifts, add_shift.events for private calendar events, and add_shift.recurring",
  );
  assertStringIncludes(
    prompt,
    "Do not send users to settings.recurring_shifts when they ask where to add a new recurring/fixed shift",
  );
  assertStringIncludes(prompt, "After creating or updating shifts");
  assertStringIncludes(
    prompt,
    "After creating a job or when pay setup blocks shift creation",
  );
  assertStringIncludes(prompt, "deeplink to Sharing");
  assertStringIncludes(prompt, "deeplink to the relevant admin destination");
  assertStringIncludes(
    prompt,
    "rendered as standalone glass buttons between message bubbles",
  );
  assertStringIncludes(
    prompt,
    "never place deeplink markdown inline inside a sentence",
  );
  assertStringIncludes(
    prompt,
    "without inserting a nearby or example deeplink",
  );
  assertStringIncludes(
    prompt,
    "always capitalize the first letter of the button text",
  );
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
  assertStringIncludes(prompt, "<jobs_and_pay>");
  assertStringIncludes(
    prompt,
    "A job cannot be used for new shifts until it has a baseline wage snapshot",
  );
  assertStringIncludes(
    prompt,
    'Use startDate "2000-01-01" and endDate equal to today\'s local date',
  );
});

Deno.test("getSystemPrompt constrains Wagey to app-relevant requests", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
  });

  assertStringIncludes(prompt, "<app_scope>");
  assertStringIncludes(prompt, "You are a Tidex product assistant");
  assertStringIncludes(
    prompt,
    "For unrelated requests, give a brief refusal or redirect",
  );
  assertStringIncludes(
    prompt,
    "Do not use web_search or web_fetch for unrelated requests",
  );
  assertStringIncludes(
    prompt,
    "Do not use web search or web fetch to satisfy off-topic requests",
  );
});

Deno.test("getSystemPrompt blocks adult-content discovery", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
  });

  assertStringIncludes(prompt, "Adult-content requests are unrelated to Tidex");
  assertStringIncludes(
    prompt,
    "Do not recommend, rank, compare, name, link to, or help discover pornographic sites, channels, studios, performers, titles, categories, or videos",
  );
  assertStringIncludes(
    prompt,
    "briefly say you can only help with Tidex shift and wage questions",
  );
});

Deno.test("getSystemPrompt suppresses auto-defaulted adjustment tax details", () => {
  const prompt = getSystemPrompt({
    accessLevel: "pro",
    used: 3,
    remaining: 37,
    bonus: 0,
  });

  assertStringIncludes(prompt, "taxTreatmentDefaulted=true");
  assertStringIncludes(
    prompt,
    "do not mention tax, tax handling, net/manual, or taxTreatment",
  );
});
