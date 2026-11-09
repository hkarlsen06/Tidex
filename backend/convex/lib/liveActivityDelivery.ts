import type { Doc } from "../_generated/dataModel";

type DeliveryStatus = Doc<"live_activity_deliveries">["status"];

/** A delivery the server may still push to: starting, active or ending. */
export function isOpenDelivery(status: DeliveryStatus): boolean {
  return status === "starting" || status === "active" || status === "ending";
}
