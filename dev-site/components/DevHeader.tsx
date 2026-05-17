import Image from 'next/image';
import Link from 'next/link';
import type { DevLocale } from '../lib/i18n-config';
import { buildLocalizedDevPath } from '../lib/paths';
import { DevLocaleToggle } from './DevLocaleToggle';
import {
  NavigationMenu,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  navigationMenuTriggerStyle,
} from './ui/navigation-menu';

interface DevHeaderProps {
  locale: DevLocale;
  dictionary: {
    nav: {
      home: string;
      projects: string;
      about: string;
      contact: string;
    };
  };
}

export function DevHeader({ locale, dictionary }: DevHeaderProps) {
  const navItems = [
    { href: buildLocalizedDevPath(locale, '/'), label: dictionary.nav.home },
    { href: buildLocalizedDevPath(locale, '/projects'), label: dictionary.nav.projects },
    { href: buildLocalizedDevPath(locale, '/about'), label: dictionary.nav.about },
    { href: buildLocalizedDevPath(locale, '/contact'), label: dictionary.nav.contact },
  ];

  return (
    <header className="fixed top-0 z-50 w-full border-b border-white/8 bg-background/78 backdrop-blur-xl">
      <div className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between px-5 sm:px-8">
        <Link
          href={buildLocalizedDevPath(locale, '/')}
          className="flex h-10 w-10 items-center justify-center overflow-hidden rounded-xl border border-white/10 bg-surface-primary transition-colors hover:border-brand-highlight/35"
          aria-label="Hjalmar Karlsen"
        >
          <Image
            src="/profile-hjalmar.webp"
            alt="Hjalmar Karlsen"
            width={80}
            height={80}
            className="h-full w-full scale-[1.18] object-cover"
            priority
          />
        </Link>

        <NavigationMenu className="hidden md:flex">
          <NavigationMenuList className="gap-1">
            {navItems.map((item) => (
              <NavigationMenuItem key={item.href}>
                <NavigationMenuLink href={item.href} className={navigationMenuTriggerStyle()}>
                  {item.label}
                </NavigationMenuLink>
              </NavigationMenuItem>
            ))}
          </NavigationMenuList>
        </NavigationMenu>

        <DevLocaleToggle currentLocale={locale} />
      </div>
    </header>
  );
}
