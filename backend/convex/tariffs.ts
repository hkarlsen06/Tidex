import { v } from "convex/values";
import { query } from "./_generated/server";
import { publicRow } from "./lib/syncWrite";

// Ports of get_tariff_types and get_tariff_versions. Public data, so no sign-in needed.

export const types = query({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("tariff_types").collect();
    return rows
      .sort((a, b) => Number(b.is_default ?? false) - Number(a.is_default ?? false) || a.display_name.localeCompare(b.display_name))
      .map(({ id, display_name, description, country, is_default }) => ({
        id,
        display_name,
        description: description ?? null,
        country,
        is_default: is_default ?? null,
      }));
  },
});

export const versions = query({
  args: { tariff_type: v.optional(v.string()) },
  handler: async (ctx, { tariff_type }) => {
    const rows = await ctx.db
      .query("tariff_versions")
      .withIndex("by_type_effective_date", (q) => q.eq("tariff_type_id", tariff_type ?? "hk_retail"))
      .order("desc")
      .collect();
    return rows.map((r) => {
      const { created_at, ...row } = publicRow(r);
      return { ...row, name: row.name ?? null };
    });
  },
});
