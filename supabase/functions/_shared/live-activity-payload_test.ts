import {
  deepStrictEqual as assertEquals,
  throws as assertThrows,
} from "node:assert/strict";
import {
  buildLiveActivityEndPayload,
  buildLiveActivityHeaders,
  buildLiveActivityStartPayload,
  LIVE_ACTIVITY_MAX_EXPIRATION_WINDOW_SECONDS,
  type LiveActivityPresentationInput,
  swiftDateSeconds,
  unixSeconds,
} from "./live-activity-payload.ts";

const startDate = new Date("2026-07-20T08:00:00.000Z");
const endDate = new Date("2026-07-20T16:00:00.000Z");
const now = new Date("2026-07-20T10:30:00.000Z");

const presentation: LiveActivityPresentationInput = {
  shiftId: "shift-123",
  date: "2026-07-20",
  start: "10:00",
  end: "18:00",
  hourly: 200,
  supplement: 25,
  gross: 1_800,
  net: 1_260,
  currency: "kr",
  startDate,
  endDate,
};

Deno.test("start payload matches ActivityKit and ShiftActivityAttributes encoding", () => {
  assertEquals(buildLiveActivityStartPayload(presentation, now), {
    aps: {
      timestamp: 1_784_543_400,
      event: "start",
      "content-state": {
        currentEarnings: 562.5,
        remainingMinutes: 330,
        progressPercent: 31.25,
      },
      "stale-date": 1_784_563_200,
      "attributes-type": "ShiftActivityAttributes",
      attributes: {
        shiftId: "shift-123",
        shiftDate: "2026-07-20",
        startTime: "10:00",
        endTime: "18:00",
        hourlyWage: 200,
        supplementRatePerHour: 25,
        totalGrossEstimate: 1_800,
        totalNetEstimate: 1_260,
        currencySymbol: "kr",
        isTemporaryClock: false,
        startDate: 806_227_200,
        endDate: 806_256_000,
      },
      alert: {
        title: { "loc-key": "liveActivity.pushStart.alertTitle" },
        body: { "loc-key": "liveActivity.pushStart.alertBody" },
      },
      "input-push-token": 1,
    },
  });
});

Deno.test("APNs fields use Unix seconds while Swift Date uses the 2001 epoch", () => {
  assertEquals(unixSeconds(startDate), 1_784_534_400);
  assertEquals(swiftDateSeconds(startDate), 806_227_200);
  assertEquals(unixSeconds(endDate), 1_784_563_200);
  assertEquals(swiftDateSeconds(endDate), 806_256_000);
});

Deno.test("end payload includes final state and dismisses immediately", () => {
  const endedAt = new Date("2026-07-20T16:01:00.000Z");

  assertEquals(buildLiveActivityEndPayload(presentation, endedAt), {
    aps: {
      timestamp: 1_784_563_260,
      event: "end",
      "content-state": {
        currentEarnings: 1_800,
        remainingMinutes: 0,
        progressPercent: 100,
      },
      "dismissal-date": 1_784_563_259,
    },
  });
});

Deno.test("live activity headers set topic, push type, priority, collapse, and bounded expiration", () => {
  const headers = buildLiveActivityHeaders({
    bundleId: "no.tidex.app",
    collapseId: "live-activity:shift-123",
    expiration: new Date("2026-07-20T12:30:00.000Z"),
    now,
  });

  assertEquals(headers, {
    "apns-topic": "no.tidex.app.push-type.liveactivity",
    "apns-push-type": "liveactivity",
    "apns-priority": "10",
    "apns-expiration": String(
      1_784_543_400 + LIVE_ACTIVITY_MAX_EXPIRATION_WINDOW_SECONDS,
    ),
    "apns-collapse-id": "live-activity:shift-123",
  });
});

Deno.test("live activity headers support low priority and reject oversized collapse IDs", () => {
  assertEquals(
    buildLiveActivityHeaders({
      bundleId: "no.tidex.app",
      expiration: new Date("2026-07-20T10:35:00.000Z"),
      priority: 5,
      now,
    }),
    {
      "apns-topic": "no.tidex.app.push-type.liveactivity",
      "apns-push-type": "liveactivity",
      "apns-priority": "5",
      "apns-expiration": "1784543700",
    },
  );

  assertThrows(
    () =>
      buildLiveActivityHeaders({
        bundleId: "no.tidex.app",
        expiration: endDate,
        collapseId: "ø".repeat(33),
        now,
      }),
    { name: "RangeError", message: /64 UTF-8 bytes/ },
  );
});
