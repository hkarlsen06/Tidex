"use client";

import { createContext, useContext, type ReactNode } from "react";

export interface ImpersonationState {
  /** Whether we're currently impersonating another user */
  isImpersonating: boolean;
  /** The target user being impersonated (if impersonating) */
  targetUserId?: string;
  /** The admin who started the impersonation (if impersonating) */
  adminUserId?: string;
  /** Display name of the target user (for UI) */
  targetUserName?: string;
  /** When the impersonation expires (ISO string) */
  expiresAt?: string;
}

const ImpersonationContext = createContext<ImpersonationState>({
  isImpersonating: false,
});

interface ImpersonationProviderProps {
  children: ReactNode;
  /** Whether we're currently impersonating */
  isImpersonating: boolean;
  /** The target user being impersonated */
  targetUserId?: string;
  /** The admin who started the impersonation */
  adminUserId?: string;
  /** Display name of the target user (for UI) */
  targetUserName?: string;
  /** When the impersonation expires (ISO string) */
  expiresAt?: string;
}

export function ImpersonationProvider({
  children,
  isImpersonating,
  targetUserId,
  adminUserId,
  targetUserName,
  expiresAt,
}: ImpersonationProviderProps) {
  return (
    <ImpersonationContext.Provider
      value={{ isImpersonating, targetUserId, adminUserId, targetUserName, expiresAt }}
    >
      {children}
    </ImpersonationContext.Provider>
  );
}

/**
 * Hook to check if we're currently impersonating another user.
 * Use this in client components to conditionally disable sensitive operations.
 */
export function useImpersonation(): ImpersonationState {
  return useContext(ImpersonationContext);
}

/**
 * Hook that throws an error message if we're impersonating.
 * Useful for displaying errors in forms when an action is blocked.
 */
export function useImpersonationRestriction(actionName: string): string | null {
  const { isImpersonating } = useImpersonation();

  if (isImpersonating) {
    return `"${actionName}" is not allowed while impersonating another user`;
  }

  return null;
}
