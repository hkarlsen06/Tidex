import Link from 'next/link';
import Image from 'next/image';
import { Clock, Layers, Shield, Zap } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import type { Locale } from '@/lib/i18n/config';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';
import { LocaleLangSetter } from './LocaleLangSetter';
import { buildLocalizedMarketingPath } from '../lib/paths';

const featureIcons = {
  shield: Shield,
  zap: Zap,
  clock: Clock,
  layers: Layers,
} as const;

interface LandingPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
}

export function LandingPage({ locale, dictionary }: LandingPageProps) {
  const marketing = dictionary.marketing;
  const heroHighlights = marketing.hero.highlights;
  const features = marketing.features.items.map((item) => ({
    ...item,
    Icon: featureIcons[item.icon as keyof typeof featureIcons] ?? Shield,
  }));
  const faqs = marketing.faq.items;
  const privacyHref = buildLocalizedMarketingPath(locale, '/privacy');
  const termsHref = buildLocalizedMarketingPath(locale, '/terms');
  const payrollDocsHref = '/docs/payroll'; // English-only route
  const mailtoHref = `mailto:${dictionary.legal.contactEmail}?subject=${encodeURIComponent(marketing.contact.emailSubject)}&body=${encodeURIComponent(marketing.contact.emailBody)}`;

  return (
    <main className="relative min-h-screen bg-background text-text-primary">
      <LocaleLangSetter locale={locale} />
      {/* Single subtle gradient accent at top */}
      <div className="pointer-events-none absolute inset-x-0 top-0 h-100 bg-linear-to-b from-brand-gradient-start/8 to-transparent" />

      <section className="relative flex min-h-svh w-full items-stretch overflow-hidden pt-[max(2rem,env(safe-area-inset-top))]">
        <div className="relative mx-auto flex w-full max-w-3xl flex-col px-6 pb-[calc(5rem+env(safe-area-inset-bottom))] sm:px-0 sm:pb-8">
          <div className="relative flex flex-1 flex-col items-center justify-center gap-7 text-center sm:gap-8">
            <div className="space-y-5 sm:space-y-7">
              <Image
                src="/icons/tidex-wordmark.webp"
                alt={marketing.hero.imageAlt}
                width={280}
                height={80}
                priority
                className="mx-auto h-auto w-[min(78vw,280px)] animate-in fade-in zoom-in-95 duration-700 sm:w-70"
              />
              <div className="space-y-4 sm:space-y-6">
                <h1 className="text-balance text-3xl font-semibold tracking-tight sm:text-5xl">
                  {marketing.hero.title}
                </h1>
                <p className="text-pretty text-base text-text-secondary sm:text-lg max-w-2xl mx-auto">
                  {marketing.hero.description}
                </p>
              </div>
            </div>
            <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-text-muted">
              {heroHighlights.map((highlight, index) => (
                <span key={highlight} className="flex items-center gap-2">
                  {index > 0 && <span className="hidden sm:inline text-border-subtle">•</span>}
                  <span className="font-medium">{highlight}</span>
                </span>
              ))}
            </div>
          </div>

          <div className="flex flex-col items-center gap-4 pt-5 sm:pt-8">
            <div className="flex justify-center">
              <MarketingLocaleToggle />
            </div>

            <div className="flex w-full flex-col gap-3 sm:mt-1 sm:flex-row sm:items-center sm:justify-center">
              <Button
                asChild
                className="h-14 w-full rounded-lg bg-brand-gradient-start px-8 text-base font-semibold text-text-inverse hover:bg-brand-gradient-mid transition-colors sm:h-11 sm:w-auto"
              >
                <a href="https://app.tidex.no">
                  {marketing.hero.primaryCta}
                </a>
              </Button>
              <Button
                asChild
                variant="outline"
                className="h-14 w-full rounded-lg border-border-subtle bg-transparent px-8 text-base font-medium text-text-primary hover:bg-surface-secondary hover:border-text-muted transition-colors sm:h-11 sm:w-auto"
              >
                <Link href="#faq">{marketing.hero.secondaryCta}</Link>
              </Button>
            </div>
            <a
              href="https://apps.apple.com/app/id6757129790"
              target="_blank"
              rel="noopener noreferrer"
              className="mt-1 block w-1/2 transition-opacity hover:opacity-80 sm:w-auto"
            >
              <Image
                src={`/badges/app-store-${locale}.svg`}
                alt={marketing.hero.appStoreCta}
                width={240}
                height={80}
                className="h-auto w-full"
              />
            </a>
          </div>
        </div>
      </section>

      <section
        id="features"
        className="px-6 pb-20 sm:pb-24 lg:pb-28"
      >
        <div className="mx-auto w-full max-w-4xl space-y-10">
          <div className="space-y-4">
            <p className="text-xs font-semibold uppercase tracking-widest text-brand-gradient-start">
              {marketing.features.eyebrow}
            </p>
            <h2 className="text-pretty text-3xl font-semibold sm:text-4xl">
              {marketing.features.heading}
            </h2>
            <p className="max-w-2xl text-pretty text-base text-text-secondary sm:text-lg">
              {marketing.features.description}
            </p>
          </div>

          <div className="grid gap-px bg-border-subtle sm:grid-cols-2 lg:grid-cols-4 rounded-xl overflow-hidden border border-border-subtle">
            {features.map(({ Icon, title, description }) => (
              <div
                key={title}
                className="group flex h-full flex-col gap-4 bg-surface-primary p-6 transition-colors hover:bg-surface-secondary"
              >
                <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-gradient-start/10 text-brand-gradient-start">
                  <Icon className="h-5 w-5" />
                </span>
                <div className="space-y-2">
                  <h3 className="text-base font-semibold text-text-primary">{title}</h3>
                  <p className="text-sm leading-relaxed text-text-secondary">{description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section
        id="faq"
        className="px-6 pb-20 sm:pb-28 lg:pb-32"
      >
        <div className="mx-auto w-full max-w-3xl">
          <div className="mb-10 space-y-4">
            <p className="text-xs font-semibold uppercase tracking-widest text-brand-gradient-start">{marketing.faq.eyebrow}</p>
            <h2 className="text-3xl font-semibold sm:text-4xl">{marketing.faq.heading}</h2>
            <p className="text-base text-text-secondary">
              {marketing.faq.description}
            </p>
          </div>

          <Accordion type="single" collapsible className="space-y-1">
            {faqs.map((faq) => (
              <AccordionItem key={faq.question} value={faq.question} className="border-b border-border-subtle last:border-b-0">
                <AccordionTrigger className="py-5 text-left text-base font-medium hover:text-brand-gradient-start transition-colors sm:text-lg">
                  {faq.question}
                </AccordionTrigger>
                <AccordionContent className="pb-5">
                  {faq.answers.map((paragraph, answerIndex) => (
                    <p key={`${faq.question}-${answerIndex}`} className="pb-3 text-base leading-relaxed text-text-secondary last:pb-0">
                      {paragraph}
                    </p>
                  ))}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>
      </section>

      <section className="px-6 pb-16 sm:pb-24">
        <div className="mx-auto flex w-full max-w-3xl flex-col items-center gap-6 rounded-xl border border-border-subtle bg-surface-secondary px-8 py-12 text-center">
          <h2 className="text-2xl font-semibold sm:text-3xl">{marketing.ctaPrimary.heading}</h2>
          <p className="max-w-xl text-pretty text-base text-text-secondary">
            {marketing.ctaPrimary.description}
          </p>
          <Button
            asChild
            className="h-11 rounded-lg bg-brand-gradient-start px-8 text-base font-semibold text-text-inverse hover:bg-brand-gradient-mid transition-colors"
          >
            <a href="https://app.tidex.no">
              {marketing.ctaPrimary.button}
            </a>
          </Button>
        </div>
      </section>

      <section className="px-6 pb-16 sm:pb-20">
        <div className="mx-auto flex w-full max-w-3xl flex-col items-center gap-5 text-center">
          <h2 className="text-xl font-semibold sm:text-2xl">{marketing.contact.heading}</h2>
          <p className="max-w-xl text-pretty text-sm text-text-secondary">
            {marketing.contact.description}
          </p>
          <Button
            asChild
            variant="outline"
            className="h-10 rounded-lg border-border-subtle bg-transparent px-6 text-sm font-medium text-text-primary hover:bg-surface-secondary hover:border-text-muted transition-colors"
          >
            <a href={mailtoHref}>
              {marketing.contact.button}
            </a>
          </Button>
        </div>
      </section>

      <footer className="border-t border-border-subtle px-6 py-8">
        <div className="mx-auto w-full max-w-4xl flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div className="text-sm text-text-muted">
            {marketing.footer.copyright}
          </div>
          <div className="flex w-full flex-col items-start gap-2 text-sm sm:w-auto sm:flex-row sm:items-center sm:justify-end sm:gap-6">
            <Link href={payrollDocsHref} className="text-text-secondary hover:text-text-primary transition-colors">
              {marketing.footer.payrollDocs}
            </Link>
            <Link href={privacyHref} className="text-text-secondary hover:text-text-primary transition-colors">
              {marketing.footer.privacy}
            </Link>
            <Link href={termsHref} className="text-text-secondary hover:text-text-primary transition-colors">
              {marketing.footer.terms}
            </Link>
          </div>
        </div>
      </footer>
    </main>
  );
}
