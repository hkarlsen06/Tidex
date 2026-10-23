import { v, type VLiteral, type VUnion } from "convex/values";

/** `v.union(v.literal(...))` with the literal types preserved. */
export function literals<const T extends readonly [string, string, ...string[]]>(
  ...values: T
): VUnion<T[number], VLiteral<T[number], "required">[], "required"> {
  return v.union(...values.map((value) => v.literal(value))) as never;
}
