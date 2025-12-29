"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname, useSearchParams, useRouter } from "next/navigation";
import { useState, useEffect } from "react";
import type { MouseEvent } from "react";
import {
  Gauge,
  Calendar,
  Plus,
  ChartNoAxesCombined,
  Share2,
  ArrowDown,
} from "lucide-react";
import { useNavigationFeedback } from "./navigation-feedback";
import { supabase } from "@/lib/supabase/browser";
import { useTranslations } from "@/lib/i18n/client";
import { useScrollContext } from "@/lib/contexts/ScrollContext";
import { useAddShiftFormSafe } from "@/lib/contexts/AddShiftFormContext";
import { useSharers } from "./SharersProvider";
import {
  useSharingViewState,
  clearSharingViewState,
} from "@/lib/hooks/useSharingViewState";

type LucideIcon = typeof Gauge;
type NavItem = {
  href: string;
  label: string;
  icon: LucideIcon;
  isCenter?: boolean;
  matchPrefix?: boolean;
};

type NavItemType = NavItem & { isSharing?: boolean };

const navItems: NavItemType[] = [
  {
    href: "/",
    label: "Home",
    icon: Gauge,
  },
  {
    href: "/shifts",
    label: "Shifts",
    icon: Calendar,
  },
  {
    href: "/shifts/add",
    label: "Add",
    icon: Plus,
    isCenter: true,
  },
  {
    href: "/stats",
    label: "Stats",
    icon: ChartNoAxesCombined,
  },
  {
    href: "/sharing",
    label: "Share",
    icon: Share2,
    isSharing: true,
  },
];

function getInitials(
  name: string | null | undefined,
  email: string | null | undefined,
): string {
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

export function NavBar() {
  const { t, locale } = useTranslations();
  const rawPathname = usePathname();
  const searchParams = useSearchParams();
  const router = useRouter();
  const { navigate, pendingPath: rawPendingPath } = useNavigationFeedback();
  const { savedSharerId, isLoaded } = useSharingViewState();
  const [showAddShiftHint, setShowAddShiftHint] = useState(false);
  const { scrollDirection } = useScrollContext();
  const addShiftForm = useAddShiftFormSafe();
  const sharers = useSharers();

  // Sort sharers: prioritize self-picked profile pictures, then OAuth avatars, then no avatar
  const sortedSharers = [...sharers].sort((a, b) => {
    const aHasProfile = !!a.profilePictureUrl;
    const bHasProfile = !!b.profilePictureUrl;
    const aHasOAuth = !!a.oauthAvatarUrl;
    const bHasOAuth = !!b.oauthAvatarUrl;

    if (aHasProfile && !bHasProfile) return -1;
    if (!aHasProfile && bHasProfile) return 1;
    if (aHasOAuth && !bHasOAuth) return -1;
    if (!aHasOAuth && bHasOAuth) return 1;

    return 0;
  });

  // Show max 4 sharers as small bubbles around the share icon
  const visibleSharers = sortedSharers.slice(0, 4);

  // Strip locale prefix from pathname for consistent nav item matching
  // usePathname() returns paths like "/no/settings" or "/en/shifts"
  const pathname = rawPathname.replace(/^\/(no|en)(?=\/|$)/, "") || "/";

  // Also strip locale from pendingPath for consistent matching
  const pendingPath = rawPendingPath
    ? rawPendingPath.replace(/^\/(no|en)(?=\/|$)/, "") || "/"
    : null;

  // Fetch shift count client-side to determine if hint should be shown
  // This is deferred to avoid blocking the initial render
  // Re-check when pathname changes so hint disappears after adding first shift
  // Convert searchParams to string for stable dependency (avoids size change errors with useSearchParams)
  const searchParamsString = searchParams?.toString() ?? "";
  useEffect(() => {
    // Immediately hide hint if optimistic shifts are being added
    // This handles the case where the user just added shifts and the DB hasn't synced yet
    const hasOptimisticShifts =
      searchParamsString.includes("optimistic") ||
      searchParamsString.includes("new") ||
      searchParamsString.includes("newRecurring");
    if (hasOptimisticShifts) {
      // Use callback to avoid synchronous setState warning
      queueMicrotask(() => setShowAddShiftHint(false));
      return;
    }

    const checkShiftCount = async () => {
      try {
        // Use getClaims() for performance - parses JWT locally without network request
        const { data: authData, error: authError } = await supabase.auth.getClaims();
        if (authError || !authData?.claims) {
          console.warn(
            "[NavBar] Failed to get user for shift count check:",
            authError,
          );
          return;
        }

        const userId = authData.claims.sub;

        const { count, error } = await supabase
          .from("user_shifts")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId);

        if (error) {
          console.warn("[NavBar] Failed to check shift count:", error);
          return;
        }

        // Update hint visibility based on current shift count
        setShowAddShiftHint((count ?? 0) === 0);
      } catch (err) {
        console.error("[NavBar] Unexpected error in shift count check:", err);
      }
    };

    checkShiftCount();
  }, [pathname, searchParamsString]);

  const isOnboardingPath = (path: string | null) => {
    if (typeof path !== "string") {
      return false;
    }

    const normalizedPath = normalizePath(path);
    return Boolean(
      normalizedPath &&
      (normalizedPath === "/onboarding" ||
        normalizedPath.startsWith("/onboarding/")),
    );
  };

  if (isOnboardingPath(pathname) || isOnboardingPath(pendingPath)) {
    return null;
  }

  const handleItemClick =
    (href: string) => (event: MouseEvent<HTMLAnchorElement>) => {
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
      navigate(href);
    };

  function normalizePath(path: string | null) {
    if (!path) {
      return null;
    }
    if (path === "/") {
      return "/";
    }
    return path.replace(/\/+$/, "");
  }

  const isEligibleForHint = (path: string | null) => {
    const normalizedPath = normalizePath(path);
    if (!normalizedPath) {
      return false;
    }
    return normalizedPath === "/" || normalizedPath === "/shifts";
  };

  const isPathActive = (item: NavItem) => {
    const normalizedHref = normalizePath(item.href);
    if (!normalizedHref) {
      return false;
    }

    const matches = (path: string | null) => {
      const normalizedPath = normalizePath(path);
      if (!normalizedPath || !normalizedHref) {
        return false;
      }

      if (normalizedHref === "/") {
        return normalizedPath === "/";
      }

      if (normalizedPath === normalizedHref) {
        return true;
      }

      if (!item.matchPrefix) {
        return false;
      }

      return normalizedPath.startsWith(`${normalizedHref}/`);
    };

    return matches(pathname) || matches(pendingPath);
  };

  const normalizedPath = normalizePath(pathname);

  // Determine if navbar should hide on scroll for current path
  const shouldHideOnScroll =
    normalizedPath === "/shifts" ||
    normalizedPath === "/stats" ||
    normalizedPath === "/sharing";

  const isHidden = shouldHideOnScroll && scrollDirection === "down";

  return (
    <nav
      className={`fixed left-0 right-0 z-40 bottom-0 transition-transform duration-300 md:hidden ${
        isHidden ? "translate-y-full" : "translate-y-0"
      }`}
    >
      {/* Background that extends into safe area on mobile - uses -bottom to extend into safe area without creeping upward */}
      <div className="absolute inset-x-0 top-0 -bottom-[env(safe-area-inset-bottom)] bg-background/80 backdrop-blur-md" />

      <div className="relative mx-auto max-w-[520px] pb-[env(safe-area-inset-bottom)]">
        <div className="flex items-center justify-around pt-4 pb-4 border-t border-border/40">
          {navItems.map((item) => {
            const isActive = isPathActive(item);
            const Icon = item.icon;

            if (item.isCenter) {
              const isOnAddPage =
                pathname === "/shifts/add" || pendingPath === "/shifts/add";
              const shouldShowHint =
                showAddShiftHint &&
                !isOnAddPage &&
                (isEligibleForHint(pathname) || isEligibleForHint(pendingPath));

              // When on add page with a registered form, clicking submits the form
              // Otherwise, navigate to the add page
              const handleCenterClick = (
                event: MouseEvent<HTMLAnchorElement>,
              ) => {
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

                if (isOnAddPage && addShiftForm?.isFormRegistered) {
                  // Trigger form submission
                  addShiftForm.submitForm();
                } else {
                  // Navigate to add page
                  navigate(item.href);
                }
              };

              return (
                <div
                  key={item.href}
                  className="relative flex items-center justify-center"
                >
                  {shouldShowHint ? (
                    <div className="pointer-events-none absolute bottom-[calc(100%+1.5rem)] left-1/2 flex -translate-x-1/2 flex-col items-center gap-3">
                      <span className="animate-gentle-pulse flex w-max flex-col items-center gap-0.5 rounded-lg border border-border-subtle bg-surface-primary px-3 py-1.5 text-center text-xs font-semibold text-text-primary shadow-app leading-tight">
                        <span>{t.navigation.addFirstShiftLine1}</span>
                        <span>{t.navigation.addFirstShiftLine2}</span>
                      </span>
                      <ArrowDown
                        className="h-10 w-10 text-brand-highlight animate-gentle-bob drop-shadow-sm"
                        strokeWidth={2}
                      />
                    </div>
                  ) : null}
                  <Link
                    href={item.href}
                    onClick={handleCenterClick}
                    prefetch={true}
                    className="flex items-center justify-center p-2 -m-2"
                  >
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradient-mid">
                      <Icon
                        className="h-6 w-6 text-text-inverse"
                        strokeWidth={2}
                      />
                    </div>
                  </Link>
                </div>
              );
            }

            // Special handling for sharing button with avatar bubbles
            if ("isSharing" in item && item.isSharing) {
              // Calculate angles to distribute bubbles evenly around the full circle
              // Each bubble is placed opposite to others for visual balance
              const getAngleForIndex = (idx: number, total: number) => {
                if (total === 1) return -135; // Single bubble at top-left
                if (total === 2) return idx === 0 ? -135 : 45; // Opposite corners: top-left, bottom-right
                // 3+ bubbles: spread evenly around the circle starting from top-left
                const startAngle = -135;
                return startAngle + idx * (360 / total);
              };

              // Determine sharing href based on current location:
              // - If on /sharing path, go to main /sharing route and clear saved state
              // - If on another page, restore saved view state (if any)
              const isOnSharingPath = normalizedPath?.startsWith("/sharing");
              const sharingHref = isOnSharingPath
                ? `/${locale}/sharing`
                : savedSharerId && isLoaded
                  ? `/${locale}/sharing?view=${savedSharerId}`
                  : `/${locale}/sharing`;

              const handleSharingClick = (
                event: MouseEvent<HTMLAnchorElement>,
              ) => {
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

                // Clear saved state when navigating to main sharing list from detail view
                if (isOnSharingPath) {
                  clearSharingViewState();
                  // Use router.push directly to bypass navigation feedback
                  // which ignores same-path navigations (it strips query params)
                  router.push(sharingHref);
                } else {
                  navigate(sharingHref);
                }
              };

              return (
                <Link
                  key={item.href}
                  href={sharingHref}
                  onClick={handleSharingClick}
                  prefetch={true}
                  className="relative flex items-center justify-center p-3 -m-3"
                >
                  {/* Small avatar bubbles positioned behind the share icon */}
                  {visibleSharers.length > 0 && (
                    <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-0">
                      {visibleSharers.map((sharer, index) => {
                        const avatarSrc =
                          sharer.profilePictureUrl || sharer.oauthAvatarUrl;
                        // Position bubbles proportionally around the icon
                        const angle = getAngleForIndex(
                          index,
                          visibleSharers.length,
                        );
                        const radius = 16; // Distance from center
                        const radians = (angle - 90) * (Math.PI / 180);
                        const x = Math.cos(radians) * radius;
                        const y = Math.sin(radians) * radius;

                        return (
                          <div
                            key={sharer.id}
                            className="absolute rounded-full border border-background bg-background"
                            style={{
                              transform: `translate(${x}px, ${y}px)`,
                            }}
                          >
                            {avatarSrc ? (
                              <Image
                                src={avatarSrc}
                                alt={sharer.firstName || "Sharer"}
                                width={18}
                                height={18}
                                className="h-[18px] w-[18px] rounded-full object-cover"
                              />
                            ) : (
                              <span className="flex h-[18px] w-[18px] items-center justify-center rounded-full bg-surface-secondary text-[8px] font-semibold text-text-primary">
                                {getInitials(sharer.firstName, sharer.email)}
                              </span>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                  <Icon
                    className={`h-6 w-6 relative z-10 ${
                      isActive ? "text-brand-highlight" : "text-text-muted"
                    } ${visibleSharers.length > 0 ? "filter-[drop-shadow(0_0_4px_hsl(var(--background)))_drop-shadow(0_0_6px_hsl(var(--background)))_drop-shadow(0_0_8px_hsl(var(--background)))]" : ""}`}
                    strokeWidth={isActive ? 2.5 : 2}
                  />
                </Link>
              );
            }

            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={handleItemClick(item.href)}
                prefetch={true}
                className="flex items-center justify-center p-3 -m-3"
              >
                <Icon
                  className={`h-6 w-6 ${
                    isActive ? "text-brand-highlight" : "text-text-muted"
                  }`}
                  strokeWidth={isActive ? 2.5 : 2}
                />
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
