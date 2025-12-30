"use client";

import Image from "next/image";
import Link from "next/link";
import { Plus, Sparkles } from "lucide-react";
import { UserMenu } from "./UserMenu";
import { OfflineIndicator } from "./OfflineIndicator";
import { NavigationMenu } from "./NavigationMenu";
import { useTranslations } from "@/lib/i18n/client";
import { useUserAvatar } from "./UserAvatarProvider";

export type TopHeaderProps = {
  userName: string;
};

export function TopHeader({ userName }: TopHeaderProps) {
  const { t, locale } = useTranslations();
  const avatarUrl = useUserAvatar();
  const cleanedName = userName.trim();
  const [firstWord] = cleanedName.split(/\s+/).filter(Boolean);
  const displayName = (firstWord ?? cleanedName) || t.common.guest;

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/80 backdrop-blur-md pt-[env(safe-area-inset-top)] md:pt-0">
      <div className="container mx-auto px-4">
        <div className="flex md:grid md:grid-cols-[1fr_auto_1fr] items-center justify-between h-16 gap-4">
          {/* Left section */}
          <div className="flex items-center gap-3">
            <Link
              href={`/${locale}`}
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
            </Link>
            <OfflineIndicator />
          </div>

          {/* Center section - Desktop navigation */}
          <NavigationMenu className="hidden md:flex" />

          {/* Right section */}
          <div className="flex items-center gap-3 justify-end">
            {/* Add button - desktop only, icon-only on md, full button on lg+ */}
            <Link
              href={`/${locale}/shifts/add`}
              className="hidden md:flex items-center justify-center rounded-2xl bg-brand-gradient-mid/10 border border-brand-gradient-mid/30 hover:bg-brand-gradient-mid/20 transition-colors h-12 w-12 lg:w-auto lg:gap-2 lg:px-4 whitespace-nowrap shrink-0"
            >
              <Plus className="h-4 w-4 text-brand-gradient-mid shrink-0" strokeWidth={2} />
              <span className="hidden lg:inline text-sm font-medium text-brand-gradient-mid">{t.common.add}</span>
            </Link>

            {/* Wagey link */}
            <Link
              href={`/${locale}/wagey`}
              className="flex items-center justify-center p-1.5 rounded-full hover:bg-surface-secondary transition-colors"
            >
              <Sparkles className="h-5 w-5 text-text-secondary" strokeWidth={2} />
            </Link>

            <UserMenu displayName={displayName} avatarUrl={avatarUrl} />
          </div>
        </div>
      </div>
    </header>
  );
}
