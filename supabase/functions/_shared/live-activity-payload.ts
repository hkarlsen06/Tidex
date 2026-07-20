const APPLE_REFERENCE_DATE_UNIX_SECONDS = 978_307_200;

export const LIVE_ACTIVITY_ATTRIBUTES_TYPE = "ShiftActivityAttributes";
export const LIVE_ACTIVITY_PUSH_TYPE = "liveactivity";
export const LIVE_ACTIVITY_PRIORITY = 10 as const;
export const LIVE_ACTIVITY_MAX_EXPIRATION_WINDOW_SECONDS = 15 * 60;

export interface LiveActivityPresentationInput {
  shiftId: string;
  date: string;
  start: string;
  end: string;
  hourly: number;
  supplement: number;
  gross: number;
  net: number | null;
  currency: string | null;
  startDate: Date;
  endDate: Date;
}

export interface LiveActivityHeadersOptions {
  bundleId: string;
  expiration: Date;
  collapseId?: string;
  priority?: 5 | 10;
  now?: Date;
}

export interface ShiftActivityContentState {
  currentEarnings: number;
  remainingMinutes: number;
  progressPercent: number;
}

export interface ShiftActivityAttributesPayload {
  shiftId: string;
  shiftDate: string;
  startTime: string;
  endTime: string;
  hourlyWage: number;
  supplementRatePerHour: number;
  totalGrossEstimate: number;
  totalNetEstimate: number | null;
  currencySymbol: string | null;
  isTemporaryClock: false;
  startDate: number;
  endDate: number;
}

export interface LiveActivityStartPayload {
  aps: {
    timestamp: number;
    event: "start";
    "content-state": ShiftActivityContentState;
    "stale-date": number;
    "attributes-type": typeof LIVE_ACTIVITY_ATTRIBUTES_TYPE;
    attributes: ShiftActivityAttributesPayload;
    alert: {
      title: { "loc-key": "liveActivity.pushStart.alertTitle" };
      body: { "loc-key": "liveActivity.pushStart.alertBody" };
    };
    "input-push-token": 1;
  };
}

export interface LiveActivityEndPayload {
  aps: {
    timestamp: number;
    event: "end";
    "content-state": ShiftActivityContentState;
    "dismissal-date": number;
  };
}

function requireValidDate(date: Date, field: string): number {
  const milliseconds = date.getTime();
  if (!Number.isFinite(milliseconds)) {
    throw new TypeError(`${field} must be a valid Date`);
  }
  return milliseconds;
}

/** Encodes ActivityKit's reserved timestamp fields as whole Unix seconds. */
export function unixSeconds(date: Date): number {
  return Math.floor(requireValidDate(date, "date") / 1_000);
}

/** Matches Foundation JSONEncoder's default Date encoding strategy. */
export function swiftDateSeconds(date: Date): number {
  return requireValidDate(date, "date") / 1_000 -
    APPLE_REFERENCE_DATE_UNIX_SECONDS;
}

function initialContentState(
  input: LiveActivityPresentationInput,
  now: Date,
): ShiftActivityContentState {
  const startMilliseconds = requireValidDate(input.startDate, "startDate");
  const endMilliseconds = requireValidDate(input.endDate, "endDate");
  const nowMilliseconds = requireValidDate(now, "now");
  const totalMilliseconds = Math.max(0, endMilliseconds - startMilliseconds);
  const elapsedMilliseconds = Math.min(
    totalMilliseconds,
    Math.max(0, nowMilliseconds - startMilliseconds),
  );

  const elapsedHours = elapsedMilliseconds / (60 * 60 * 1_000);
  const remainingMinutes = Math.max(
    0,
    Math.floor((endMilliseconds - nowMilliseconds) / (60 * 1_000)),
  );
  const progressPercent = totalMilliseconds === 0
    ? 100
    : elapsedMilliseconds / totalMilliseconds * 100;

  return {
    currentEarnings: elapsedHours * (input.hourly + input.supplement),
    remainingMinutes,
    progressPercent,
  };
}

function attributes(
  input: LiveActivityPresentationInput,
): ShiftActivityAttributesPayload {
  return {
    shiftId: input.shiftId,
    shiftDate: input.date,
    startTime: input.start,
    endTime: input.end,
    hourlyWage: input.hourly,
    supplementRatePerHour: input.supplement,
    totalGrossEstimate: input.gross,
    totalNetEstimate: input.net,
    currencySymbol: input.currency,
    isTemporaryClock: false,
    startDate: swiftDateSeconds(input.startDate),
    endDate: swiftDateSeconds(input.endDate),
  };
}

export function buildLiveActivityStartPayload(
  input: LiveActivityPresentationInput,
  now: Date = new Date(),
): LiveActivityStartPayload {
  return {
    aps: {
      timestamp: unixSeconds(now),
      event: "start",
      "content-state": initialContentState(input, now),
      "stale-date": unixSeconds(input.endDate),
      "attributes-type": LIVE_ACTIVITY_ATTRIBUTES_TYPE,
      attributes: attributes(input),
      alert: {
        title: { "loc-key": "liveActivity.pushStart.alertTitle" },
        body: { "loc-key": "liveActivity.pushStart.alertBody" },
      },
      "input-push-token": 1,
    },
  };
}

export function buildLiveActivityEndPayload(
  input: LiveActivityPresentationInput,
  now: Date = new Date(),
): LiveActivityEndPayload {
  const timestamp = unixSeconds(now);

  return {
    aps: {
      timestamp,
      event: "end",
      "content-state": {
        currentEarnings: input.gross,
        remainingMinutes: 0,
        progressPercent: 100,
      },
      "dismissal-date": timestamp - 1,
    },
  };
}

export function buildLiveActivityHeaders(
  options: LiveActivityHeadersOptions,
): Record<string, string> {
  const bundleId = options.bundleId.trim();
  if (bundleId.length === 0) {
    throw new TypeError("bundleId must not be empty");
  }

  const nowSeconds = unixSeconds(options.now ?? new Date());
  const requestedExpiration = unixSeconds(options.expiration);
  const expiration = Math.max(
    nowSeconds,
    Math.min(
      requestedExpiration,
      nowSeconds + LIVE_ACTIVITY_MAX_EXPIRATION_WINDOW_SECONDS,
    ),
  );

  const headers: Record<string, string> = {
    "apns-topic": `${bundleId}.push-type.liveactivity`,
    "apns-push-type": LIVE_ACTIVITY_PUSH_TYPE,
    "apns-priority": String(options.priority ?? LIVE_ACTIVITY_PRIORITY),
    "apns-expiration": String(expiration),
  };

  if (options.collapseId !== undefined) {
    const collapseIdBytes =
      new TextEncoder().encode(options.collapseId).byteLength;
    if (collapseIdBytes > 64) {
      throw new RangeError("collapseId must not exceed 64 UTF-8 bytes");
    }
    headers["apns-collapse-id"] = options.collapseId;
  }

  return headers;
}
