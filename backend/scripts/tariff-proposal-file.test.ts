import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat, symlink } from "node:fs/promises";
import { join } from "node:path";
import { writePrivateProposal } from "./tariff-proposal-file";

let directory: string;
beforeEach(async () => {
  directory = await mkdtemp("/tmp/tidex-tariff-proposal-test-");
});
afterEach(async () => {
  await rm(directory, { recursive: true });
});

test("a private proposal is readable only by its owner and never overwrites a file", async () => {
  const path = join(directory, "proposal.json");
  await writePrivateProposal(path, '{"wage":274.58}');
  expect((await stat(path)).mode & 0o777).toBe(0o600);
  expect(await readFile(path, "utf8")).toBe('{"wage":274.58}');
  await expect(writePrivateProposal(path, "replacement")).rejects.toThrow();
  expect(await readFile(path, "utf8")).toBe('{"wage":274.58}');
});

test("a private proposal cannot follow a directory symlink outside tmp", async () => {
  const link = join(directory, "outside");
  await symlink(import.meta.dir, link);
  await expect(
    writePrivateProposal(join(link, "private-customer-wages.json"), "private"),
  ).rejects.toThrow("inside /tmp");
});

test("a private proposal cannot overwrite a symlink target", async () => {
  const target = join(directory, "original.json");
  await writePrivateProposal(target, "original");
  const link = join(directory, "proposal.json");
  await symlink(target, link);
  await expect(writePrivateProposal(link, "replacement")).rejects.toThrow();
  expect(await readFile(target, "utf8")).toBe("original");
});
