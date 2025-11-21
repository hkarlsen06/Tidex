/**
 * River Router
 *
 * Organizes multiple streams into a single router (TRPC-like pattern)
 */

import type { RiverRouter } from "./types";

/**
 * Create a River router
 *
 * @example
 * ```ts
 * const myRouter = createRiverRouter({
 *   chat: chatStream,
 *   translate: translateStream,
 * });
 * ```
 */
export function createRiverRouter<T extends RiverRouter>(router: T): T {
  return router;
}
