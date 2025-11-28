'use client';

import Link from 'next/link';
import { useTranslations } from '@/lib/i18n/client';

export function AppFooter() {
  const { t, locale } = useTranslations();
  const footer = t.footer;

  return (
    <footer className="mt-auto border-t border-border-subtle bg-background pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-0">
      <div className="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8">
        <div className="grid gap-x-4 gap-y-6 grid-cols-2 lg:grid-cols-4">
          {/* Product Column */}
          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-text-primary uppercase tracking-wide">{footer.product.title}</h3>
            <ul className="space-y-1.5">
              <li>
                <Link
                  href={`/${locale}/settings/subscription`}
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.product.subscription}
                </Link>
              </li>
              <li>
                <Link
                  href={`/${locale}/settings/data`}
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.product.exportData}
                </Link>
              </li>
            </ul>
          </div>

          {/* Resources Column */}
          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-text-primary uppercase tracking-wide">{footer.resources.title}</h3>
            <ul className="space-y-1.5">
              <li>
                <a
                  href="https://tidex.no/docs/payroll"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.resources.payrollDocs}
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/kkarlsen06"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors inline-flex items-center gap-1"
                >
                  {footer.resources.github}
                  <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path fillRule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" clipRule="evenodd" />
                  </svg>
                </a>
              </li>
            </ul>
          </div>

          {/* Legal Column */}
          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-text-primary uppercase tracking-wide">{footer.legal.title}</h3>
            <ul className="space-y-1.5">
              <li>
                <a
                  href={`https://tidex.no/${locale}/privacy`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.legal.privacy}
                </a>
              </li>
              <li>
                <a
                  href={`https://tidex.no/${locale}/terms`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.legal.terms}
                </a>
              </li>
            </ul>
          </div>

          {/* Company Column */}
          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-text-primary uppercase tracking-wide">{footer.company.title}</h3>
            <ul className="space-y-1.5">
              <li>
                <a
                  href="mailto:contact@tidex.no"
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.company.support}
                </a>
              </li>
              <li>
                <a
                  href="https://tidex.no"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-text-secondary hover:text-text-primary transition-colors"
                >
                  {footer.company.website}
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom Bar */}
        <div className="mt-4 py-4 border-t border-border-subtle">
          <p className="text-xs text-text-muted text-center">
            {footer.copyright}
          </p>
        </div>
      </div>
    </footer>
  );
}
