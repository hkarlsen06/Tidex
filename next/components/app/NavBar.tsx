"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";
import type { MouseEvent } from "react";
import {
  Gauge,
  Calendar,
  Plus,
  ChartNoAxesCombined,
  Share2,
} from "lucide-react";
import { useNavigationFeedback } from "./navigation-feedback";
import { useTranslations } from "@/lib/i18n/client";
import { useScrollContext } from "@/lib/contexts/ScrollContext";
import { useAddShiftFormSafe } from "@/lib/contexts/AddShiftFormContext";
import { useSharers } from "./SharersProvider";
import { clearSharingViewState } from "@/lib/hooks/useSharingViewState";
import { useHasNativeTabBar } from "@/lib/contexts/NativeTabBarContext";

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
    href: "/dashboard",
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
  const { locale } = useTranslations();
  const rawPathname = usePathname();
  const { navigate, pendingPath: rawPendingPath } = useNavigationFeedback();
  const { scrollDirection } = useScrollContext();
  const addShiftForm = useAddShiftFormSafe();
  const sharers = useSharers();
  const isNativeIOS = useHasNativeTabBar();

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

  // Hide web NavBar on native iOS (native UITabBar handles navigation)
  if (isNativeIOS) {
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
    // Treat "/" as "/dashboard" for consistent comparison
    if (path === "/") {
      return "/dashboard";
    }
    return path.replace(/\/+$/, "");
  }

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

      // Dashboard is the home route
      if (normalizedHref === "/dashboard") {
        return normalizedPath === "/dashboard";
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
      data-web-navbar
      className={`fixed left-0 right-0 z-40 bottom-0 transition-transform duration-300 md:hidden ${isHidden ? "translate-y-full" : "translate-y-0"
        }`}
    >
      {/* Background that extends into safe area on mobile - uses -bottom to extend into safe area without creeping upward */}
      <div className="absolute inset-x-0 top-0 -bottom-[env(safe-area-inset-bottom)] bg-background/80 backdrop-blur-md" />

      <div className="relative mx-auto max-w-130 pb-[env(safe-area-inset-bottom)]">
        <div className="flex items-center justify-around pt-4 pb-4 border-t border-border/40">
          {navItems.map((item) => {
            const isActive = isPathActive(item);
            const Icon = item.icon;

            if (item.isCenter) {
              const isOnAddPage =
                pathname === "/shifts/add" || pendingPath === "/shifts/add";

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

              // Always use the base sharing path without query params
              // This ensures consistent navigation behavior and avoids triggering
              // parent loading states due to query param changes
              const isOnSharingPath = normalizedPath?.startsWith("/sharing");
              const sharingHref = `/${locale}/sharing`;

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

                // Clear saved state when navigating to main sharing list
                if (isOnSharingPath) {
                  clearSharingViewState();
                }

                // Use the standard navigate() for consistent behavior with other nav items
                // This leverages prefetch cache and avoids double skeleton flash
                navigate(sharingHref);
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
                                className="h-4.5 w-4.5 rounded-full object-cover"
                              />
                            ) : (
                              <span className="flex h-4.5 w-4.5 items-center justify-center rounded-full bg-surface-secondary text-[8px] font-semibold text-text-primary">
                                {getInitials(sharer.firstName, sharer.email)}
                              </span>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                  <Icon
                    className={`h-6 w-6 relative z-10 ${isActive ? "text-brand-highlight" : "text-text-muted"
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
                  className={`h-6 w-6 ${isActive ? "text-brand-highlight" : "text-text-muted"
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
