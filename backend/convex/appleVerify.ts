"use node";

import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { v } from "convex/values";
import { internalAction } from "./_generated/server";

// Verifies App Store Server Notifications V2 with Apple's library, which needs Node's
// crypto. Ported from the verification half of the apple-server-notifications Edge
// Function, which needed a Deno workaround for the same library.

const BUNDLE_ID = process.env.APPLE_APP_BUNDLE_ID ?? "no.tidex.app";
const APP_APPLE_ID = Number(process.env.APPLE_APP_APPLE_ID ?? "6757129790");
const ROOT_CA_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
];

let rootCertificates: Promise<Buffer[]> | null = null;

function roots() {
  rootCertificates ??= Promise.all(
    ROOT_CA_URLS.map(async (url) => {
      const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
      if (!response.ok) throw new Error(`Failed to fetch Apple root certificate: ${url}`);
      return Buffer.from(await response.arrayBuffer());
    }),
  ).catch((error) => {
    rootCertificates = null;
    throw error;
  });
  return rootCertificates;
}

/** The environment the payload claims, to pick the verifier. Verification still checks it. */
function environmentHint(signedPayload: string): "Production" | "Sandbox" | null {
  try {
    const payload = JSON.parse(Buffer.from(signedPayload.split(".")[1] ?? "", "base64url").toString());
    const environment = payload?.data?.environment ?? payload?.summary?.environment ?? payload?.appData?.environment;
    return environment === "Production" || environment === "Sandbox" ? environment : null;
  } catch {
    return null;
  }
}

/** The verified notification with its transaction and renewal info, or null if invalid. */
export const verify = internalAction({
  args: { signed_payload: v.string() },
  handler: async (_ctx, { signed_payload }) => {
    const certs = await roots();
    const hint = environmentHint(signed_payload);
    const production = () => new SignedDataVerifier(certs, false, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID);
    const sandbox = () => new SignedDataVerifier(certs, false, Environment.SANDBOX, BUNDLE_ID);
    const verifiers = hint === "Sandbox" ? [sandbox()] : hint === "Production" ? [production()] : [production(), sandbox()];
    for (const verifier of verifiers) {
      try {
        const notification = await verifier.verifyAndDecodeNotification(signed_payload);
        const decode = async <T>(signed: string | undefined, read: (s: string) => Promise<T>) => {
          if (signed === undefined) return null;
          try {
            return await read(signed);
          } catch (error) {
            console.error("[apple-notifications] Failed to decode signed info:", error);
            return null;
          }
        };
        const data = notification.data;
        // JSON round trip: Convex can only return plain values.
        return JSON.parse(
          JSON.stringify({
            notification,
            transactionInfo: await decode(data?.signedTransactionInfo, (s) => verifier.verifyAndDecodeTransaction(s)),
            renewalInfo: await decode(data?.signedRenewalInfo, (s) => verifier.verifyAndDecodeRenewalInfo(s)),
          }),
        );
      } catch (error) {
        console.warn("[apple-notifications] Verification attempt failed:", error instanceof Error ? error.message : error);
      }
    }
    return null;
  },
});
