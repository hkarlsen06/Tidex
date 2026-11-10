import { expect, test } from "bun:test";
import { invitePreview } from "../convex/sharing";

// Only the database and the signed-in identity are fakes. The query runs its real
// viewer lookup and block rule.
function context(shares = []) {
  const tables = {
    users: [
      { id: "viewer", clerk_user_id: "clerk-viewer", role: "user" },
      { id: "inviter", clerk_user_id: "clerk-inviter", role: "user", name: "Ola", email: "ola@example.com" },
    ],
    profiles: [{ id: "inviter", username: "ola" }],
    user_settings: [],
    shift_shares: shares,
  };
  return {
    auth: { getUserIdentity: async () => ({ subject: "clerk-viewer" }) },
    db: {
      query(table) {
        let rows = tables[table] ?? [];
        const index = { eq(field, value) { rows = rows.filter((r) => r[field] === value); return index; } };
        const query = {
          withIndex(_name, range) { range(index); return query; },
          unique: async () => rows[0] ?? null,
          first: async () => rows[0] ?? null,
        };
        return query;
      },
    },
  };
}

const share = (owner_id, viewer_id, blocked_by_user_id) => ({ owner_id, viewer_id, blocked_by_user_id });

test("the opener sees who sent the link, without their email", async () => {
  const preview = await invitePreview._handler(context(), { user_id: "inviter" });
  expect(preview).toEqual({
    id: "inviter", firstName: "Ola", username: "ola",
    profilePictureUrl: null, oauthAvatarUrl: null, alreadySharing: false,
  });
});

test("a link from someone who does not exist names nobody", async () => {
  expect(await invitePreview._handler(context(), { user_id: "missing" })).toBeNull();
});

for (const [who, blocker] of [["the inviter", "inviter"], ["the opener", "viewer"]]) {
  for (const [direction, owner, viewer] of [["inviter's", "inviter", "viewer"], ["opener's", "viewer", "inviter"]]) {
    test(`a block by ${who} on the ${direction} share hides the inviter`, async () => {
      const ctx = context([share(owner, viewer, blocker)]);
      expect(await invitePreview._handler(ctx, { user_id: "inviter" })).toBeNull();
    });
  }
}

test("an existing share without a block shows the inviter as already shared with", async () => {
  const preview = await invitePreview._handler(context([share("viewer", "inviter")]), { user_id: "inviter" });
  expect(preview.alreadySharing).toBe(true);
});
