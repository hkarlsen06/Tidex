import { dirname, resolve } from "node:path";
import { realpath, writeFile } from "node:fs/promises";

export async function writePrivateProposal(
  path: string,
  contents: string,
): Promise<void> {
  const target = resolve(path);
  const parent = await realpath(dirname(target));
  if (
    parent !== "/private/tmp" &&
    !parent.startsWith("/private/tmp/") &&
    parent !== "/tmp" &&
    !parent.startsWith("/tmp/")
  ) {
    throw new Error("Private proposal directory must resolve inside /tmp");
  }
  await writeFile(target, contents, { mode: 0o600, flag: "wx" });
}
