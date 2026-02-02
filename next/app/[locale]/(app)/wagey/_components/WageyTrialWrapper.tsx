"use client";

/**
 * Wagey Trial Wrapper
 *
 * Wraps the showcase and interface for free users, allowing them
 * to test Wagey with 3 messages before needing to subscribe.
 * Trial state is client-side only - navigating away resets it.
 */

import { useState } from "react";
import { WageyShowcase } from "./WageyShowcase";
import { WageyInterface } from "./WageyInterface";
import type { WageyAccessResult } from "@/lib/wagey/types";

type WageyTrialWrapperProps = {
  userId: string;
  userName?: string;
  wageyAccess: WageyAccessResult;
};

export function WageyTrialWrapper({ userId, userName, wageyAccess }: WageyTrialWrapperProps) {
  const [isTrialMode, setIsTrialMode] = useState(false);

  // Use the real access data from server, but override hasAccess for trial mode
  const trialAccess: WageyAccessResult = {
    ...wageyAccess,
    hasAccess: true, // Allow access during trial (server returns hasAccess: false for free users)
  };

  if (!isTrialMode) {
    return <WageyShowcase onTryWagey={() => setIsTrialMode(true)} />;
  }

  return (
    <WageyInterface
      userId={userId}
      userName={userName}
      wageyAccess={trialAccess}
    />
  );
}
