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
    <header className="sticky top-4 z-50 px-4">
      <div className="flex items-center justify-between rounded-3xl border border-border-subtle bg-surface-primary/80 px-2 py-2 shadow-app-lg backdrop-blur">
        <div className="flex items-center gap-3">
          <a
            href="https://tidex.no/"
            className="inline-flex items-center justify-center px-2"
            aria-label={t.header.goToTidex}
          >
            <Image
              src="/icons/image.png"
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
    </header>
  );
}
