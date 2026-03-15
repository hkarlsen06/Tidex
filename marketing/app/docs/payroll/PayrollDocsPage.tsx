'use client';

import { useEffect } from 'react';
import { Button } from '../../../components/ui/button';
import { Separator } from '../../../components/ui/separator';
import { PayrollDocsRenderer } from '@/components/payroll-docs/PayrollDocsRenderer';

interface PayrollDocsType {
  badge: string;
  title: string;
  subtitle: string;
  navigation: ReadonlyArray<{ readonly id: string; readonly label: string }>;
  bugReportCta: {
    heading: string;
    description: string;
    buttonText: string;
    emailSubject: string;
    emailBody: string;
  };
  sections: readonly any[];
}

interface PayrollDocsPageProps {
  docs: PayrollDocsType;
}

export function PayrollDocsPage({ docs }: PayrollDocsPageProps) {
  const handleBugReport = () => {
    const subject = encodeURIComponent(docs.bugReportCta.emailSubject);
    const body = encodeURIComponent(docs.bugReportCta.emailBody);
    window.location.href = `mailto:contact@tidex.no?subject=${subject}&body=${body}`;
  };

  const scrollToSection = (id: string, updateHash = true) => {
    const element = document.getElementById(id);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth', block: 'start' });
      if (updateHash) {
        window.history.pushState(null, '', `#${id}`);
      }
    }
  };

  // Handle initial hash navigation on page load
  useEffect(() => {
    const hash = window.location.hash.slice(1); // Remove the # character
    if (hash) {
      // Small delay to ensure content is rendered
      setTimeout(() => {
        scrollToSection(hash, false);
      }, 100);
    }
  }, []);

  // Handle hash changes (browser back/forward)
  useEffect(() => {
    const handleHashChange = () => {
      const hash = window.location.hash.slice(1);
      if (hash) {
        scrollToSection(hash, false);
      }
    };

    window.addEventListener('hashchange', handleHashChange);
    return () => window.removeEventListener('hashchange', handleHashChange);
  }, []);

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b border-border-subtle bg-surface-primary">
        <div className="container mx-auto px-6 py-10 sm:px-8 sm:py-12 lg:py-14">
          <div className="max-w-4xl space-y-4">
            <span className="text-xs font-semibold uppercase tracking-widest text-brand-gradient-start">
              {docs.badge}
            </span>
            <h1 className="text-2xl font-bold leading-tight text-text-primary sm:text-3xl lg:text-4xl">
              {docs.title}
            </h1>
            <p className="max-w-2xl text-base leading-relaxed text-text-secondary">
              {docs.subtitle}
            </p>
          </div>
        </div>
      </header>

      {/* Simple Navigation */}
      <nav className="sticky top-0 z-10 border-b border-border-subtle bg-surface-primary/95 backdrop-blur-xs">
        <div className="container mx-auto px-6 sm:px-8">
          <div className="flex items-center gap-4 py-3">
            {/* Back Button */}
            <a
              href="/"
              className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-text-secondary transition-colors hover:bg-surface-secondary hover:text-text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="shrink-0"
              >
                <path d="m15 18-6-6 6-6" />
              </svg>
              <span className="hidden sm:inline">Back</span>
            </a>

            {/* Divider */}
            <div className="h-6 w-px bg-border-subtle" />

            {/* Section Navigation */}
            <ul className="flex flex-1 gap-1 overflow-x-auto">
              {docs.navigation.map((item) => (
                <li key={item.id}>
                  <button
                    onClick={() => scrollToSection(item.id)}
                    className="whitespace-nowrap rounded-lg px-4 py-2 text-sm font-medium text-text-secondary transition-colors hover:bg-surface-secondary hover:text-text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  >
                    {item.label}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="container mx-auto px-6 py-12 sm:px-8 sm:py-16 lg:py-20">
        <div className="mx-auto max-w-4xl space-y-20 sm:space-y-24">
          {docs.sections.map((section) => (
            <section key={section.id} id={section.id} className="scroll-mt-20">
              <PayrollDocsRenderer section={section} />
            </section>
          ))}
        </div>

        <Separator className="my-16 sm:my-20" />

        {/* Bug Report CTA */}
        <section className="rounded-xl border border-border-subtle bg-surface-secondary p-10 text-center sm:p-12">
          <div className="mx-auto max-w-xl space-y-5">
            <h2 className="text-xl font-semibold leading-tight text-text-primary sm:text-2xl">
              {docs.bugReportCta.heading}
            </h2>
            <p className="text-base leading-relaxed text-text-secondary">
              {docs.bugReportCta.description}
            </p>
            <Button
              onClick={handleBugReport}
              className="h-11 rounded-lg bg-brand-gradient-start px-8 text-base font-semibold text-text-inverse hover:bg-brand-gradient-mid transition-colors"
            >
              {docs.bugReportCta.buttonText}
            </Button>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-border-subtle py-8">
        <div className="container mx-auto px-6 text-center sm:px-8">
          <p className="text-sm text-text-muted">
            © 2026 Tidex — Complete transparency in payroll calculations
          </p>
        </div>
      </footer>
    </div>
  );
}
