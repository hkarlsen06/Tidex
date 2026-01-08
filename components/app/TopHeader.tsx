"use client";

import Link from "next/link";
import { Plus, Sparkles } from "lucide-react";
import { UserMenu } from "./UserMenu";
import { OfflineIndicator } from "./OfflineIndicator";
import { NavigationMenu } from "./NavigationMenu";
import { ImpersonationIndicator } from "./ImpersonationIndicator";
import { useTranslations } from "@/lib/i18n/client";
import { useUserAvatar } from "./UserAvatarProvider";
import { useImpersonation } from "@/components/providers/ImpersonationProvider";

export type TopHeaderProps = {
  userName: string;
};

export function TopHeader({ userName }: TopHeaderProps) {
  const { t, locale } = useTranslations();
  const avatarUrl = useUserAvatar();
  const { isImpersonating } = useImpersonation();
  const cleanedName = userName.trim();
  const [firstWord] = cleanedName.split(/\s+/).filter(Boolean);
  const displayName = (firstWord ?? cleanedName) || t.common.guest;

  // Both native iOS and web PWA use CSS env() for safe area
  // The CSS rule for [data-top-header] provides a fallback on native iOS
  // md:pt-0 removes padding on desktop where there's no notch
  const topPadding = "pt-[env(safe-area-inset-top)] md:pt-0";

  return (
    <header data-top-header className={`sticky top-0 z-50 w-full border-b border-border/40 bg-background/80 backdrop-blur-md ${topPadding}`}>
      <div className="container mx-auto px-4">
        <div className="flex md:grid md:grid-cols-[1fr_auto_1fr] items-center justify-between h-16 gap-4">
          {/* Left section */}
          <div className="flex items-center gap-3">
            {isImpersonating ? (
              <ImpersonationIndicator />
            ) : (
              <Link
                href={`/${locale}`}
                className="inline-flex items-center justify-center"
                aria-label={t.header.goToTidex}
              >
                <svg width="28" height="28" viewBox="-40 -40 611 627" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                  <defs>
                    <linearGradient id="headerLogoGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                      <stop offset="0%" stopColor="#00D4FF"/>
                      <stop offset="50%" stopColor="#7B61FF"/>
                      <stop offset="100%" stopColor="#9B4DCA"/>
                    </linearGradient>
                  </defs>
                  <g transform="matrix(1.388889,0,0,1.388889,-541.775787,-1494.193122)">
                    <path d="M756,1077c-60.8334,0.1203 -288.1826,-2.7163 -349,0c-6.0816,0.2716 -15.2292,2.138 -16,14c-0.692,10.6494 -1.6711,37.4598 0,48c0.7708,4.862 5.9602,14.1855 16,14c20.2977,-0.375 82.7506,-0.6596 105,0c13.022,0.386 25.9275,10.7905 26,26c0.2359,49.5227 -0.2537,227.5927 0,270c0.262,43.7816 89.9981,9.2281 90,-32c0.0023,-47.7505 -0.4143,-195.8051 0,-240c0.089,-9.5004 9.6491,-23.8549 25,-24c21.5403,-0.2035 81.9476,0.5129 102,0c9.1601,-0.2343 16.715,-5.0697 17,-18c0.2255,-10.2309 0.2826,-30.2076 0,-41c-0.2013,-7.6885 -5.2183,-17.0213 -16,-17Z" fill="url(#headerLogoGradient)"/>
                  </g>
                </svg>
              </Link>
            )}
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
