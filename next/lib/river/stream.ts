/**
 * River Stream Builder
 *
 * Fluent API for creating type-safe stream definitions
 */

import type { ZodSchema } from "zod";
import type {
  RiverStreamDefinition,
  RiverProvider,
  RiverRunnerFn,
} from "./types";

/**
 * Stream builder class
 */
class RiverStreamBuilder<TChunk, TAdapterRequest, TInput = never> {
  private _inputSchema?: ZodSchema<TInput>;
  private _provider?: RiverProvider;
  private _runner?: RiverRunnerFn<TInput, TChunk, TAdapterRequest>;

  /**
   * Set the input validation schema
   */
  input<TNewInput>(schema: ZodSchema<TNewInput>) {
    const builder =
      new RiverStreamBuilder<TChunk, TAdapterRequest, TNewInput>();
    builder._inputSchema = schema as ZodSchema<any>;
    builder._provider = this._provider;
    builder._runner = this._runner as any;
    return builder;
  }

  /**
   * Set the stream provider (default or Redis)
   */
  provider(provider: RiverProvider) {
    this._provider = provider;
    return this;
  }

  /**
   * Set the runner function (stream logic)
   */
  runner(fn: RiverRunnerFn<TInput, TChunk, TAdapterRequest>) {
    this._runner = fn;
    return this;
  }

  /**
   * Build the stream definition
   */
  build(): RiverStreamDefinition<TInput, TChunk, TAdapterRequest> {
    if (!this._inputSchema || !this._provider || !this._runner) {
      throw new Error(
        "Stream definition incomplete. Must call input(), provider(), and runner()"
      );
    }

    return {
      inputSchema: this._inputSchema,
      provider: this._provider,
      runner: this._runner,
    };
  }
}

/**
 * Create a new River stream
 *
 * @example
 * ```ts
 * const myStream = createRiverStream<ChunkType, NextRequest>()
 *   .input(z.object({ prompt: z.string() }))
 *   .provider(defaultRiverProvider())
 *   .runner(async ({ input, stream }) => {
 *     await stream.appendChunk({ text: "Hello" });
 *     await stream.close();
 *   });
 * ```
 */
export function createRiverStream<TChunk, TAdapterRequest>() {
  return new RiverStreamBuilder<TChunk, TAdapterRequest>();
}
