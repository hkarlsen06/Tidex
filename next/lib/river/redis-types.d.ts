/**
 * Minimal type definitions for ioredis
 * Used by provider-redis.ts without requiring the full ioredis package
 */

declare module "ioredis" {
  export default class Redis {
    xadd(key: string, id: string, ...args: string[]): Promise<string>;
    xread(
      ...args: Array<string | number>
    ): Promise<Array<[string, Array<[string, string[]]>]> | null>;
  }
}
