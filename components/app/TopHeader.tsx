"use client";

import Image from "next/image";
import { UserMenu } from "./UserMenu";
import { OfflineIndicator } from "./OfflineIndicator";
import { NavigationMenu } from "./NavigationMenu";
import { useTranslations } from "@/lib/i18n/client";

export type TopHeaderProps = {
  userName: string;
  avatarUrl?: string | null;
};

export function TopHeader({ userName, avatarUrl }: TopHeaderProps) {
  const { t } = useTranslations();
  const cleanedName = userName.trim();
  const [firstWord] = cleanedName.split(/\s+/).filter(Boolean);
  const displayName = (firstWord ?? cleanedName) || "Guest";

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/80 backdrop-blur-md pt-[env(safe-area-inset-top)] md:pt-0">
      <div className="container mx-auto flex h-16 items-center justify-between px-4">
        <div className="flex items-center gap-3">
          <a
            href="https://tidex.no/"
            className="inline-flex items-center justify-center"
            aria-label={t.header.goToTidex}
          >
            <Image
              src="/icons/tidex-wordmark.webp"
              alt="Tidex"
              width={100}
              height={28}
              className="h-7 w-auto"
              priority
            />
          </a>
          <OfflineIndicator />
        </div>

        {/* Desktop navigation - hidden on mobile */}
        <NavigationMenu className="hidden md:flex" />

        <UserMenu displayName={displayName} avatarUrl={avatarUrl ?? null} />
      </div>
    </header>
  );
}
