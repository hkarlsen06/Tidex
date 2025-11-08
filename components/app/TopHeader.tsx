"use client";

import Image from "next/image";
import { UserMenu } from "./UserMenu";
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
    <header className="sticky top-0 z-50 bg-surface-primary/95 backdrop-blur md:bg-transparent pt-[env(safe-area-inset-top)] md:pt-0">
      <div className="mx-auto max-w-[520px] md:px-4">
        <div className="flex items-center justify-between pt-2 pb-2 px-4 border-b border-border-subtle md:bg-surface-primary/95 md:backdrop-blur md:border md:rounded-2xl md:shadow-app-lg">
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
          </div>

          <UserMenu displayName={displayName} avatarUrl={avatarUrl ?? null} />
        </div>
      </div>
    </header>
  );
}
