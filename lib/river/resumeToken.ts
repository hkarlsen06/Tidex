/**
 * Resumption Token Utilities
 *
 * Encode/decode resumption tokens for resumable streams
 */

import type { ResumptionTokenData } from "./types";
import { RiverError } from "./types";
import { Result, ok, err } from "neverthrow";

/**
 * Encode resumption token data to base64 string
 */
export function encodeResumptionToken(data: ResumptionTokenData): string {
  const json = JSON.stringify(data);
  return Buffer.from(json).toString("base64");
}

/**
 * Decode base64 resumption token to data
 */
export function decodeResumptionToken(
  token: string
): Result<ResumptionTokenData, RiverError> {
  try {
    const json = Buffer.from(token, "base64").toString("utf-8");
    const data = JSON.parse(json) as ResumptionTokenData;

    // Validate structure
    if (
      !data.providerId ||
      !data.routerStreamKey ||
      !data.streamStorageId ||
      !data.streamRunId
    ) {
      return err(
        new RiverError(
          "Invalid resumption token structure",
          "internal",
          { token }
        )
      );
    }

    return ok(data);
  } catch (error) {
    return err(
      new RiverError("Failed to decode resumption token", "internal", {
        token,
        cause: error,
      })
    );
  }
}
