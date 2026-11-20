import type { ActionCtx } from "../../_generated/server";

// One entry per MCP tool. The pure part (ToolSpec) lives in lib/mcp/<area>.ts so tests can
// import it without Convex; mcp<Area>.ts adds run and exports the area's McpTool list.

/** A write tool also needs read access, because its result shows the user's data. */
export type Scope = "read" | "write";

export type ToolDefinition = {
  name: string;
  title: string;
  description: string;
  inputSchema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
    additionalProperties: false;
  };
  annotations: {
    title: string;
    readOnlyHint: boolean;
    destructiveHint?: boolean;
    idempotentHint?: boolean;
    openWorldHint: boolean;
  };
};

export type ToolSpec<P = unknown> = {
  definition: ToolDefinition;
  scope: Scope;
  /** Checked arguments. Throws ToolError with a message for the agent. */
  parse: (args: Record<string, unknown>) => P;
};

export type McpTool<P = unknown> = ToolSpec<P> & {
  run(ctx: ActionCtx, userId: string, args: P): Promise<unknown>;
};

export const tool = <P>(spec: ToolSpec<P>, run: McpTool<P>["run"]): McpTool<P> => ({ ...spec, run });
