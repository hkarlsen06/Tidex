import { v, ConvexError } from "convex/values";
import { query } from "./_generated/server";
import { publicRow } from "./lib/syncWrite";
import {
  requireCatalogueRevision,
  tariffCatalogue,
} from "./lib/tariffCatalogue";

export const types = query({
  args: { catalogue_revision: v.optional(v.string()) },
  handler: async (ctx, { catalogue_revision }) => {
    if (catalogue_revision !== undefined) {
      requireCatalogueRevision(catalogue_revision);
      return tariffCatalogue
        .map((entry) => entry.type)
        .sort(
          (a, b) =>
            Number(b.is_default) - Number(a.is_default) ||
            a.display_name.localeCompare(b.display_name),
        );
    }
    const rows = await ctx.db.query("tariff_types").collect();
    return rows
      .sort(
        (a, b) =>
          Number(b.is_default ?? false) - Number(a.is_default ?? false) ||
          a.display_name.localeCompare(b.display_name),
      )
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
  args: {
    tariff_type: v.optional(v.string()),
    catalogue_revision: v.optional(v.string()),
  },
  handler: async (ctx, { tariff_type, catalogue_revision }) => {
    const type = tariff_type ?? "hk_retail";
    const rows = await ctx.db
      .query("tariff_versions")
      .withIndex("by_type_effective_date", (q) => q.eq("tariff_type_id", type))
      .order("desc")
      .collect();
    const legacy = rows.map((r) => {
      const { created_at, ...row } = publicRow(r);
      return { ...row, name: row.name ?? null };
    });
    if (catalogue_revision === undefined) return legacy;
    requireCatalogueRevision(catalogue_revision);
    const entry = tariffCatalogue.find(
      (candidate) => candidate.type.id === type,
    );
    if (!entry)
      throw new ConvexError("Unsupported tariff in this catalogue revision");
    const historical = legacy
      .filter((row) => row.effective_date < entry.version.effective_date)
      .map((row) => ({
        ...row,
        categories: entry.version.categories.filter((category) =>
          Object.hasOwn(row.rates, String(category.level)),
        ),
      }));
    return [entry.version, ...historical];
  },
});
