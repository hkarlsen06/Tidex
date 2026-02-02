"use client";

import { createContext, useContext, type ReactNode } from "react";

const UserAvatarContext = createContext<string | null>(null);

export function useUserAvatar() {
  return useContext(UserAvatarContext);
}

type UserAvatarProviderProps = {
  avatarUrl: string | null;
  children: ReactNode;
};

/**
 * Client component that provides user avatar URL via context.
 * Used with Suspense to stream avatar data without blocking initial render.
 */
export function UserAvatarProvider({ avatarUrl, children }: UserAvatarProviderProps) {
  return (
    <UserAvatarContext value={avatarUrl}>
      {children}
    </UserAvatarContext>
  );
}
