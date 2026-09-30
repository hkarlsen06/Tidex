import Image from 'next/image';
import { ArrowRight } from 'lucide-react';
import tidexAppIcon from '@/public/brand/tidex-app-icon.webp';
import tidexWordmark from '@/public/brand/tidex-wordmark-dark.svg';
import { Button } from '../../../components/ui/button';
import {
  PayrollDocsRenderer,
  type PayrollDocsSection,
} from '@/components/payroll-docs/PayrollDocsRenderer';

export interface PayrollDocs {
  badge: string;
  title: string;
  /** Part of `title` shown in the accent colour. */
  titleEmphasis: string;
  subtitle: string;
  updated: string;
  quickLinksHeading: string;
  quickLinks: Array<{ question: string; id: string }>;
  navigation: Array<{ id: string; label: string }>;
  bugReportCta: {
    heading: string;
    description: string;
    buttonText: string;
    emailSubject: string;
    emailBody: string;
  };
  sections: PayrollDocsSection[];
}

export function PayrollDocsPage({ docs }: { docs: PayrollDocs }) {
  const [titleStart, titleEnd] = docs.title.split(docs.titleEmphasis);
  const bugReportHref = `mailto:contact@tidex.no?subject=${encodeURIComponent(docs.bugReportCta.emailSubject)}&body=${encodeURIComponent(docs.bugReportCta.emailBody)}`;

  return (
    <div className="min-h-screen bg-background">
      <header className="relative overflow-hidden bg-[linear-gradient(100deg,#0a0f2e_0%,#1f1d58_100%)] px-6 pb-14 pt-[max(1rem,env(safe-area-inset-top))] sm:px-8 sm:pb-16">
        <div className="pointer-events-none absolute right-[-15%] top-[-20%] h-[32rem] w-[32rem] rounded-full bg-[radial-gradient(circle,#4c86ea40,transparent_65%)]" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-linear-to-t from-background to-transparent" />

        <div className="relative mx-auto max-w-4xl">
          <a
            href="/"
            aria-label="Tidex home"
            className="inline-grid w-32 grid-cols-[90fr_325fr] items-center gap-[1.891%] py-4 transition-opacity hover:opacity-80 sm:w-36"
          >
            <Image src={tidexAppIcon} alt="" priority className="h-auto w-full" />
            <Image src={tidexWordmark} alt="Tidex" priority className="h-auto w-full" />
          </a>

          <p className="mt-8 text-xs font-medium uppercase tracking-[0.22em] text-brand-highlight sm:mt-12">
            {docs.badge}
          </p>
          <h1 className="mt-3 text-balance text-4xl leading-[1.08] tracking-[-0.015em] text-text-primary sm:text-5xl lg:text-6xl">
            {titleStart}
            <em className="not-italic text-brand-highlight">{docs.titleEmphasis}</em>
            {titleEnd}
          </h1>
          <p className="mt-4 max-w-2xl text-pretty text-lg leading-relaxed text-white/75">
            {docs.subtitle}
          </p>
          <p className="mt-3 text-sm text-text-muted">{docs.updated}</p>

          <h2 className="mt-10 text-sm font-medium text-text-secondary sm:mt-12">
            {docs.quickLinksHeading}
          </h2>
          <ul className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {docs.quickLinks.map((link) => (
              <li key={link.id}>
                <a
                  href={`#${link.id}`}
                  className="group flex h-full items-center justify-between gap-3 rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-sm font-medium text-text-primary transition-colors hover:border-brand-highlight/40 hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  {link.question}
                  <ArrowRight
                    aria-hidden="true"
                    className="size-4 shrink-0 text-text-muted transition-transform group-hover:translate-x-0.5 group-hover:text-brand-highlight"
                  />
                </a>
              </li>
            ))}
          </ul>
        </div>
      </header>

      <nav
        aria-label="Sections"
        className="sticky top-0 z-10 border-b border-border-subtle bg-background/85 px-6 backdrop-blur-xl sm:px-8"
      >
        <div className="mx-auto max-w-4xl">
          <ul className="-mx-2.5 flex overflow-x-auto py-2 [scrollbar-width:none]">
            {docs.navigation.map((item) => (
              <li key={item.id}>
                <a
                  href={`#${item.id}`}
                  className="block whitespace-nowrap rounded-lg px-2.5 py-2 text-sm font-medium text-text-secondary transition-colors hover:bg-surface-secondary hover:text-text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      </nav>

      {/* Main Content */}
      <main className="mx-auto box-content max-w-4xl px-6 py-12 sm:px-8 sm:py-16 lg:py-20">
        <div className="space-y-20 sm:space-y-24">
          {docs.sections.map((section) => (
            <section key={section.id} id={section.id} className="scroll-mt-20">
              <PayrollDocsRenderer section={section} />
            </section>
          ))}
        </div>

        <hr className="my-16 border-border-subtle sm:my-20" />

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
              asChild
              className="h-11 rounded-lg bg-brand-gradient-start px-8 text-base font-semibold text-text-inverse hover:bg-brand-gradient-mid transition-colors"
            >
              <a href={bugReportHref}>{docs.bugReportCta.buttonText}</a>
            </Button>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-border-subtle py-8">
        <div className="container mx-auto px-6 text-center sm:px-8">
          <p className="text-sm text-text-muted">© 2026 Tidex</p>
        </div>
      </footer>
    </div>
  );
}
