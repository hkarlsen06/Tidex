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
    <header className="fixed top-0 z-50 w-full border-b border-border/40 bg-background/80 backdrop-blur-md">
      <div className="container mx-auto flex h-16 items-center justify-between px-4">
        <Link href={buildLocalizedDevPath(locale, '/')} className="text-xl font-bold text-text-primary">
          HK
        </Link>

        <NavigationMenu className="hidden md:flex">
          <NavigationMenuList>
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
