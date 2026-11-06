import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { writeFile } from "node:fs/promises";
import { writePrivateProposal } from "./tariff-proposal-file";
import {
  CATALOGUE_REVISION,
  exportCatalogue,
  overdueTariffs,
  tariffCatalogue,
  unavailableTariffs,
  validateCatalogue,
} from "../convex/lib/tariffCatalogue";

const { positionals, values } = parseArgs({
  args: process.argv.slice(2),
  allowPositionals: true,
  strict: true,
  options: {
    "as-of": { type: "string" },
    output: { type: "string" },
    url: { type: "string" },
    "env-file": { type: "string" },
    "exclude-user-id": { type: "string", multiple: true },
    "job-id": { type: "string" },
    "snapshot-id": { type: "string" },
    "expected-revision": { type: "string" },
    "from-date": { type: "string" },
  },
});
const command = positionals[0] ?? "validate";
const today = new Date().toISOString().slice(0, 10);
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
async function publicQuery(path: string, args: object): Promise<unknown> {
  const url = values.url ?? "https://convex.tidex.no";
  const response = await fetch(new URL("/api/query", url), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ path, args, format: "json" }),
  });
  if (!response.ok)
    throw new Error(`Query failed with HTTP ${response.status}`);
  const payload: unknown = await response.json();
  if (!record(payload) || payload.status !== "success")
    throw new Error("Tariff query returned an error");
  return payload.value;
}
async function internalQuery(name: string, args: object): Promise<unknown> {
  if (!values["env-file"])
    throw new Error("Internal read requires explicit --env-file");
  const env = resolve(values["env-file"]);
  const child = Bun.spawn(
    ["bunx", "convex", "run", name, JSON.stringify(args), "--env-file", env],
    { cwd: resolve(import.meta.dir, ".."), stdout: "pipe", stderr: "pipe" },
  );
  const [stdout, stderr, exit] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  if (exit !== 0)
    throw new Error(`Internal read failed: ${stderr.slice(0, 2000)}`);
  return JSON.parse(stdout);
}
async function output(value: unknown) {
  const text = JSON.stringify(value, null, 2) + "\n";
  if (values.output) {
    const target = resolve(values.output);
    if (command === "proposal") {
      await writePrivateProposal(target, text);
    } else {
      await writeFile(target, text);
    }
  } else process.stdout.write(text);
}
try {
  validateCatalogue(tariffCatalogue);
  switch (command) {
    case "validate":
      await output({
        revision: CATALOGUE_REVISION,
        agreements: tariffCatalogue.length,
        categories: tariffCatalogue.reduce(
          (sum, e) => sum + e.version.categories.length,
          0,
        ),
        unavailable: unavailableTariffs,
      });
      break;
    case "export":
      await output(exportCatalogue());
      break;
    case "review": {
      const overdue = overdueTariffs(values["as-of"] ?? today);
      await output({
        revision: CATALOGUE_REVISION,
        as_of: values["as-of"] ?? today,
        overdue,
      });
      if (overdue.length) process.exitCode = 1;
      break;
    }
    case "diff": {
      const differences = [];
      for (const entry of tariffCatalogue) {
        const rows = await publicQuery("tariffs:versions", {
          tariff_type: entry.type.id,
        });
        if (
          !Array.isArray(rows) ||
          rows.some(
            (row) => !record(row) || typeof row.effective_date !== "string",
          )
        )
          throw new Error(`Malformed tariff response for ${entry.type.id}`);
        const previous = rows[0];
        differences.push({
          id: entry.type.id,
          action: previous ? "new_reviewed_version" : "new_agreement",
          before: previous ?? null,
          after: entry.version,
        });
      }
      await output({ revision: CATALOGUE_REVISION, writes: 0, differences });
      break;
    }
    case "impact": {
      const excluded = values["exclude-user-id"] ?? [];
      if (!excluded.length)
        throw new Error(
          "Provide the exact App Review account with --exclude-user-id",
        );
      const pages: unknown[] = [];
      let cursor: string | null = null;
      do {
        const page = await internalQuery("tariffMaintenance:impact", {
          as_of: values["as-of"] ?? today,
          exclude_user_ids: excluded,
          cursor,
        });
        if (
          !record(page) ||
          typeof page.done !== "boolean" ||
          typeof page.cursor !== "string"
        )
          throw new Error("Malformed impact inventory");
        pages.push(page.counts);
        cursor = page.done ? null : page.cursor;
      } while (cursor !== null);
      await output({ revision: CATALOGUE_REVISION, writes: 0, pages });
      break;
    }
    case "proposal": {
      if (
        !values.output ||
        (!resolve(values.output).startsWith("/private/tmp/") &&
          !resolve(values.output).startsWith("/tmp/"))
      )
        throw new Error("Private proposal requires --output /tmp/<file>.json");
      const expectedRevision = Number(values["expected-revision"]);
      if (
        !values["job-id"] ||
        !values["snapshot-id"] ||
        !Number.isSafeInteger(expectedRevision) ||
        expectedRevision < 0 ||
        !values["from-date"]
      )
        throw new Error(
          "Proposal requires --job-id, --snapshot-id, --expected-revision and --from-date",
        );
      const proposal = await internalQuery(
        "tariffMaintenance:correctionProposal",
        {
          job_id: values["job-id"],
          expected_snapshot_id: values["snapshot-id"],
          expected_revision: expectedRevision,
          from_date: values["from-date"],
          exclude_user_ids: values["exclude-user-id"] ?? [],
        },
      );
      await output(proposal);
      break;
    }
    default:
      throw new Error(
        "Commands: validate, export, review, diff, impact, proposal. All remote commands are read-only.",
      );
  }
} catch (error) {
  process.stderr.write(
    `${error instanceof Error ? error.message : "Tariff command failed"}\n`,
  );
  process.exitCode = 1;
}
