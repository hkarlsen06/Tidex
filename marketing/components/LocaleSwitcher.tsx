"use client";

import Link from "next/link";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { locales, localeNames, type Locale } from "@/lib/i18n/config";

/**
 * Client-side locale switcher with "Norsk" / "English" labels.
 * Can be used on any page - switches locale while preserving the current path.
 */
export function LocaleSwitcher() {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const prefersReducedMotion = useReducedMotion();

  // Extract current locale from pathname
  const pathLocale = pathname.split('/')[1] as Locale;
  const currentLocale = locales.includes(pathLocale) ? pathLocale : locales[0];

  // Build the new path with the target locale
  const buildLocalePath = (locale: Locale) => {
    // Create regex from locales array to stay in sync with config
    const localePattern = new RegExp(`^/(${locales.join("|")})`);
    const pathWithoutLocale = pathname.replace(localePattern, "");
    return `/${locale}${pathWithoutLocale || ""}`;
  };

  useEffect(() => {
    setIsOpen(false);
  }, [pathname]);

  useEffect(() => {
    const handlePointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsOpen(false);
      }
    };

    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, []);

  const otherLocales = locales.filter((locale) => locale !== currentLocale);
  const springTransition = prefersReducedMotion
    ? { duration: 0 }
    : { type: "spring" as const, stiffness: 420, damping: 32, mass: 0.8 };

  return (
    <motion.div
      ref={rootRef}
      layout
      transition={springTransition}
      className="inline-flex items-center rounded-full border border-white/6 bg-white/[0.015] p-[0.2rem] text-[0.95rem] font-medium text-text-muted backdrop-blur-sm"
    >
      <button
        type="button"
        aria-expanded={isOpen}
        aria-label="Change language"
        onClick={() => setIsOpen((open) => !open)}
        className="inline-flex items-center rounded-full bg-white/[0.04] px-3.5 py-1.25 text-text-secondary transition-colors hover:bg-white/[0.05]"
      >
        <span>{localeNames[currentLocale]}</span>
      </button>

      <AnimatePresence initial={false}>
        {isOpen
          ? otherLocales.map((locale) => (
              <motion.div
                key={locale}
                layout
                initial={prefersReducedMotion ? false : { width: 0, opacity: 0, marginLeft: 0 }}
                animate={prefersReducedMotion ? {} : { width: "auto", opacity: 1, marginLeft: 4 }}
                exit={prefersReducedMotion ? {} : { width: 0, opacity: 0, marginLeft: 0 }}
                transition={springTransition}
                className="overflow-hidden"
              >
                <Link
                  href={buildLocalePath(locale)}
                  onClick={() => setIsOpen(false)}
                  className="inline-flex items-center whitespace-nowrap rounded-full px-3.5 py-1.25 text-text-muted transition-colors hover:bg-white/[0.02] hover:text-text-secondary"
                >
                  {localeNames[locale]}
                </Link>
              </motion.div>
            ))
          : null}
      </AnimatePresence>
    </motion.div>
  );
}
