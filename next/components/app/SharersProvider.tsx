"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { SharedUser } from "@/data-access/sharing";

const SharersContext = createContext<SharedUser[]>([]);

export function useSharers() {
  return useContext(SharersContext);
}

type SharersProviderProps = {
  sharers: SharedUser[];
  children?: ReactNode;
};

/**
 * Client component that provides sharers data via context.
 * Used with Suspense to stream sharers data without blocking initial render.
 */
export function SharersProvider({ sharers, children }: SharersProviderProps) {
  return (
    <SharersContext value={sharers}>
      {children}
    </SharersContext>
  );
}
