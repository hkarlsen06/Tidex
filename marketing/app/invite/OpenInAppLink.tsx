'use client';

import { useSyncExternalStore } from 'react';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function inviterIdFromPath(): string | null {
  const id = window.location.pathname.split('/').filter(Boolean)[1] ?? '';
  return UUID.test(id) ? id.toLowerCase() : null;
}

// iOS opens the app from a tidex.no/invite link tapped in Messages or another app, but not from a
// link typed or pasted into Safari, nor from a link on tidex.no itself. This custom-scheme link
// opens the invite for people who already have the app. The id only exists in the URL, because
// every invite path serves this one static page.
export function OpenInAppLink({ label }: { label: string }) {
  const inviterId = useSyncExternalStore(
    () => () => {},
    inviterIdFromPath,
    () => null,
  );
  if (!inviterId) return null;
  return (
    <a
      href={`tidex://invite/${inviterId}`}
      className="inline-flex h-13 items-center justify-center rounded-full border border-white/15 px-7 text-base font-semibold text-text-primary transition-colors hover:bg-white/[0.04]"
    >
      {label}
    </a>
  );
}
