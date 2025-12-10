"use client";

import Image from "next/image";
import Link from "next/link";
import { Plus, Share2 } from "lucide-react";
import { UserMenu } from "./UserMenu";
import { OfflineIndicator } from "./OfflineIndicator";
import { NavigationMenu } from "./NavigationMenu";
import { useTranslations } from "@/lib/i18n/client";
import { useSharers } from "./SharersProvider";
import { useUserAvatar } from "./UserAvatarProvider";

export type TopHeaderProps = {
  userName: string;
};

function getInitials(name: string | null | undefined, email: string | null | undefined): string {
  if (name) {
    return name
      .split(" ")
      .map((n) => n[0])
      .join("")
      .toUpperCase()
      .slice(0, 2);
  }
  if (email) {
    return email[0].toUpperCase();
  }
  return "?";
}

export function TopHeader({ userName }: TopHeaderProps) {
  const { t, locale } = useTranslations();
  const sharers = useSharers();
  const avatarUrl = useUserAvatar();
  const cleanedName = userName.trim();
  const [firstWord] = cleanedName.split(/\s+/).filter(Boolean);
  const displayName = (firstWord ?? cleanedName) || t.common.guest;

  // Sort sharers: prioritize self-picked profile pictures, then OAuth avatars, then no avatar
  const sortedSharers = [...sharers].sort((a, b) => {
    const aHasProfile = !!a.profilePictureUrl;
    const bHasProfile = !!b.profilePictureUrl;
    const aHasOAuth = !!a.oauthAvatarUrl;
    const bHasOAuth = !!b.oauthAvatarUrl;

    // Self-picked photos first
    if (aHasProfile && !bHasProfile) return -1;
    if (!aHasProfile && bHasProfile) return 1;

    // OAuth avatars second
    if (aHasOAuth && !bHasOAuth) return -1;
    if (!aHasOAuth && bHasOAuth) return 1;

    return 0;
  });

  // Show all sharers (with or without avatar), max 3
  const visibleSharers = sortedSharers.slice(0, 3);

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
              className="hidden md:flex items-center gap-2 rounded-2xl bg-brand-gradient-mid/10 px-4 h-12 border border-brand-gradient-mid/30 hover:bg-brand-gradient-mid/20 transition-colors"
            >
              <Plus className="h-4 w-4 text-brand-gradient-mid" strokeWidth={2} />
              <span className="text-sm font-medium text-brand-gradient-mid">{t.common.add}</span>
            </Link>

            {/* Share link with stacked sharer avatars */}
            <Link
              href={`/${locale}/sharing`}
              className="flex items-center"
            >
              {/* Stacked avatars - render in reverse so priority users are closest to share icon */}
              {visibleSharers.length > 0 && (
                <div className="flex items-center">
                  {[...visibleSharers].reverse().map((sharer, index) => {
                    const avatarSrc = sharer.profilePictureUrl || sharer.oauthAvatarUrl;
                    // Higher index = further right = higher z-index (on top)
                    return (
                      <div
                        key={sharer.id}
                        className="relative rounded-full border-2 border-background bg-background"
                        style={{
                          marginRight: -10,
                          zIndex: index,
                        }}
                      >
                        {avatarSrc ? (
                          <Image
                            src={avatarSrc}
                            alt={sharer.firstName || "Sharer"}
                            width={24}
                            height={24}
                            className="h-6 w-6 rounded-full object-cover"
                          />
                        ) : (
                          <span className="flex h-6 w-6 items-center justify-center rounded-full bg-surface-secondary text-[10px] font-semibold text-text-primary">
                            {getInitials(sharer.firstName, sharer.email)}
                          </span>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
              {/* Share icon overlaps the rightmost avatar */}
              <div
                className="relative p-1 rounded-full bg-background"
                style={{ zIndex: visibleSharers.length }}
              >
                <Share2 className="h-5 w-5 text-text-secondary" strokeWidth={2} />
              </div>
            </Link>

            <UserMenu displayName={displayName} avatarUrl={avatarUrl} />
          </div>
        </div>
      </div>
    </header>
  );
}
