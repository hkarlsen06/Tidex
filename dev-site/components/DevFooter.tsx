import Link from 'next/link';
import { Github, Mail } from 'lucide-react';
import type { DevLocale } from '../lib/i18n-config';
import type { DevDictionary } from '../lib/dictionaries';
import { buildLocalizedDevPath } from '../lib/paths';
import { EMAIL, GITHUB_URL } from '../lib/contact-info';

interface DevFooterProps {
  locale: DevLocale;
  dictionary: DevDictionary;
}

export function DevFooter({ locale, dictionary }: DevFooterProps) {
  const navItems = [
    { href: buildLocalizedDevPath(locale, '/'), label: dictionary.nav.home },
    { href: buildLocalizedDevPath(locale, '/projects'), label: dictionary.nav.projects },
    { href: buildLocalizedDevPath(locale, '/about'), label: dictionary.nav.about },
    { href: buildLocalizedDevPath(locale, '/contact'), label: dictionary.nav.contact },
  ];

  return (
    <footer className="border-t border-white/6 px-5 py-10 sm:px-8">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-sm font-medium text-text-primary">Hjalmar Karlsen</p>
          <p className="mt-1 text-xs text-text-muted">
            © 2026 · {dictionary.footer.rights}
          </p>
        </div>

        <nav className="flex flex-wrap gap-x-5 gap-y-2" aria-label={dictionary.nav.menu}>
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="text-sm text-text-muted transition-colors hover:text-text-primary"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          <a
            href={`mailto:${EMAIL}`}
            aria-label={dictionary.contact.email.cta}
            className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 text-text-muted transition-colors hover:border-brand-highlight/40 hover:text-text-primary"
          >
            <Mail className="h-4 w-4" />
          </a>
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label={dictionary.contact.github.cta}
            className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 text-text-muted transition-colors hover:border-brand-highlight/40 hover:text-text-primary"
          >
            <Github className="h-4 w-4" />
          </a>
        </div>
      </div>
    </footer>
  );
}
