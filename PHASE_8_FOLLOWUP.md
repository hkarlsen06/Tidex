# Phase 8 Follow-up

Phase 8 is not required for the shift snapshot chat feature to work.

It is post-rollout cleanup and should only be done after adoption is safe.

## Status

- Phases 1-7 are the feature-complete rollout.
- Phase 8 is technical debt cleanup.
- Phase 8 is not a release blocker.

## What Phase 8 Means

Remove legacy preview bridging that still exists for rollout compatibility, including older `lastMessageHasImage`-based paths, only after all active iOS callers have migrated to `lastMessagePreviewKind` semantics and the gated rollout is fully released.

## When To Do It

Do phase 8 only when:

- shift snapshot sending has been released behind the centralized gate
- decode/render/fallback/draft support is already live everywhere needed
- old callers depending on legacy preview compatibility are no longer needed
- it is safe to remove `last_message_has_image` compatibility handling
