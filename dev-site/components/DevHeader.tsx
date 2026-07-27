'use client';

import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Menu, X } from 'lucide-react';
import type { DevLocale } from '../lib/i18n-config';
import { buildLocalizedDevPath, stripDevLocalePrefix } from '../lib/paths';
import { DevLocaleToggle } from './DevLocaleToggle';

interface DevHeaderProps {
  locale: DevLocale;
  dictionary: {
    nav: {
      home: string;
      projects: string;
      about: string;
      contact: string;
      menu: string;
      close: string;
    };
  };
}

export function DevHeader({ locale, dictionary }: DevHeaderProps) {
  const pathname = usePathname() ?? '/';
  const currentRoute = stripDevLocalePrefix(pathname);
  const [isMenuOpen, setIsMenuOpen] = useState(false);

  const navItems = [
    { route: '/', label: dictionary.nav.home },
    { route: '/projects', label: dictionary.nav.projects },
    { route: '/about', label: dictionary.nav.about },
    { route: '/contact', label: dictionary.nav.contact },
  ].map((item) => ({ ...item, href: buildLocalizedDevPath(locale, item.route) }));

  useEffect(() => {
    setIsMenuOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!isMenuOpen) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setIsMenuOpen(false);
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isMenuOpen]);

  return (
    <header className="fixed top-0 z-50 w-full border-b border-white/6 bg-background/70 backdrop-blur-xl">
      <div className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between gap-4 px-5 sm:px-8">
        <Link
          href={buildLocalizedDevPath(locale, '/')}
          className="group flex items-center gap-3"
          aria-label="Hjalmar Karlsen"
        >
          <span className="relative flex h-9 w-9 items-center justify-center overflow-hidden rounded-full ring-1 ring-white/12 transition group-hover:ring-brand-highlight/45">
            <Image
              src="/profile-hjalmar.webp"
              alt=""
              width={80}
              height={80}
              className="h-full w-full scale-[1.18] object-cover"
              priority
            />
          </span>
          <span className="hidden text-sm font-semibold tracking-[-0.01em] text-text-primary sm:block">
            Hjalmar Karlsen
          </span>
        </Link>

        <nav className="hidden items-center gap-1 md:flex" aria-label={dictionary.nav.menu}>
          {navItems.map((item) => {
            const isActive = currentRoute === item.route;

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={isActive ? 'page' : undefined}
                className={`rounded-full px-3.5 py-2 text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-white/8 text-text-primary'
                    : 'text-text-muted hover:bg-white/4 hover:text-text-primary'
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-2">
          <DevLocaleToggle currentLocale={locale} />
          <button
            type="button"
            onClick={() => setIsMenuOpen((open) => !open)}
            aria-expanded={isMenuOpen}
            aria-label={isMenuOpen ? dictionary.nav.close : dictionary.nav.menu}
            className="flex h-10 w-10 items-center justify-center rounded-full border border-white/10 text-text-secondary transition-colors hover:text-text-primary md:hidden"
          >
            {isMenuOpen ? <X className="h-4.5 w-4.5" /> : <Menu className="h-4.5 w-4.5" />}
          </button>
        </div>
      </div>

      {isMenuOpen ? (
        <nav
          className="border-t border-white/6 bg-background/95 px-5 pb-4 pt-2 backdrop-blur-xl md:hidden"
          aria-label={dictionary.nav.menu}
        >
          {navItems.map((item) => {
            const isActive = currentRoute === item.route;

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={isActive ? 'page' : undefined}
                className={`block rounded-xl px-4 py-3 text-base font-medium transition-colors ${
                  isActive ? 'bg-white/8 text-text-primary' : 'text-text-secondary hover:bg-white/4'
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>
      ) : null}
    </header>
  );
}
