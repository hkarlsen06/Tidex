"use client";

import { useSyncExternalStore, useTransition } from "react";
import { AlertTriangle, X } from "lucide-react";
import { Button } from "@/components/app/Button";
import { logWebAppSunsetBannerDismissal } from "@/app/actions/logWebAppSunsetBannerDismissal";
import { useTranslations } from "@/lib/i18n/client";

const DISMISS_STORAGE_KEY = "tidex:web-app-sunset-banner:dismissed:2026-04-01";
const DISMISS_EVENT_NAME = "tidex:web-app-sunset-banner:changed";

function subscribe(onStoreChange: () => void) {
  window.addEventListener("storage", onStoreChange);
  window.addEventListener(DISMISS_EVENT_NAME, onStoreChange);

  return () => {
    window.removeEventListener("storage", onStoreChange);
    window.removeEventListener(DISMISS_EVENT_NAME, onStoreChange);
  };
}

function getDismissedSnapshot() {
  try {
    return window.localStorage.getItem(DISMISS_STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

export function WebAppSunsetBanner() {
  const { t } = useTranslations();
  const isDismissed = useSyncExternalStore(subscribe, getDismissedSnapshot, () => false);
  const [_isPending, startTransition] = useTransition();

  const handleDismiss = () => {
    try {
      window.localStorage.setItem(DISMISS_STORAGE_KEY, "1");
      window.dispatchEvent(new Event(DISMISS_EVENT_NAME));
    } catch {
      // Ignore storage failures; the banner will remain visible in this session.
    }

    startTransition(async () => {
      const result = await logWebAppSunsetBannerDismissal();

      if (!result.success) {
        console.error("Failed to log web app sunset banner dismissal");
      }
    });
  };

  if (isDismissed) {
    return null;
  }

  return (
    <section className="border-b border-warning/30 bg-warning-subtle text-warning-foreground">
      <div className="container mx-auto px-4 pb-3 pt-[calc(env(safe-area-inset-top)+0.75rem)] md:py-3">
        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-start gap-3">
            <div className="mt-0.5 rounded-full bg-warning/15 p-2">
              <AlertTriangle className="h-4 w-4 shrink-0" />
            </div>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-text-primary">
                {t.header.webAppSunset.title}
              </p>
              <p className="mt-1 text-sm text-text-secondary">
                {t.header.webAppSunset.description}
              </p>
            </div>
          </div>

          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleDismiss}
            className="shrink-0 border-warning/40 bg-background/80 text-text-primary hover:bg-background"
            aria-label={t.header.webAppSunset.dismiss}
          >
            <X className="h-4 w-4 sm:mr-1" />
            <span className="hidden sm:inline">{t.header.webAppSunset.dismiss}</span>
          </Button>
        </div>
      </div>
    </section>
  );
}
