"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { MouseEvent } from "react";
import { ArrowLeft, Loader2 } from "lucide-react";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useTranslations } from "@/lib/i18n/client";
import { defaultLocale } from "@/lib/i18n/config";

export function SettingsBackButton() {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();
  const { t } = useTranslations();

  // Extract locale from current pathname
  const localeMatch = pathname.match(/^\/(en|no|de)/);
  const locale = localeMatch ? localeMatch[1] : defaultLocale;

  const settingsPath = `/${locale}/settings`;
  const isNavigating = pendingPath === settingsPath;

  const handleClick = (event: MouseEvent<HTMLAnchorElement>) => {
    if (
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      event.button !== 0
    ) {
      return;
    }

    event.preventDefault();
    navigate(settingsPath);
  };

  return (
    <Link
      href={settingsPath}
      onClick={handleClick}
      className="inline-flex items-center gap-2 text-sm text-text-secondary hover:text-text-primary transition-colors lg:hidden"
    >
      {isNavigating ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <ArrowLeft className="h-4 w-4" />
      )}
      <span>{t.common.back}</span>
    </Link>
  );
}
