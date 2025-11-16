"use client";

import Image from "next/image";
import Link from "next/link";
import { Plus } from "lucide-react";
import { UserMenu } from "./UserMenu";
import { OfflineIndicator } from "./OfflineIndicator";
import { NavigationMenu } from "./NavigationMenu";
import { useTranslations } from "@/lib/i18n/client";

export type TopHeaderProps = {
  userName: string;
  avatarUrl?: string | null;
};

export function TopHeader({ userName, avatarUrl }: TopHeaderProps) {
  const { t, locale } = useTranslations();
  const cleanedName = userName.trim();
  const [firstWord] = cleanedName.split(/\s+/).filter(Boolean);
  const displayName = (firstWord ?? cleanedName) || "Guest";

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/80 backdrop-blur-md pt-[env(safe-area-inset-top)] md:pt-0">
      <div className="container mx-auto px-4">
        <div className="flex md:grid md:grid-cols-[1fr_auto_1fr] items-center justify-between h-16 gap-4">
          {/* Left section */}
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

          {/* Center section - Desktop navigation */}
          <NavigationMenu className="hidden md:flex" />

          {/* Right section */}
          <div className="flex items-center gap-3 justify-end">
            {/* Add button - desktop only, matches UserMenu style with CTA color */}
            <Link
              href={`/${locale}/shifts/add`}
              className="hidden md:flex items-center gap-2 rounded-2xl bg-brand-gradientMid/10 px-4 h-12 border border-brand-gradientMid/30 hover:bg-brand-gradientMid/20 transition-colors"
            >
              <Plus className="h-4 w-4 text-brand-gradientMid" strokeWidth={2} />
              <span className="text-sm font-medium text-brand-gradientMid">{t.common.add}</span>
            </Link>

            <UserMenu displayName={displayName} avatarUrl={avatarUrl ?? null} />
          </div>
        </div>
      </div>
    </header>
  );
}
