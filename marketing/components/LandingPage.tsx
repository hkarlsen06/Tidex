import Link from 'next/link';
import Image from 'next/image';
import { Clock, Layers, Shield, Zap } from 'lucide-react';
import { Button } from '@/components/app/Button';
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
import ViewportHeightSetter from './ViewportHeightSetter';
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
  path?: string;
}

export function LandingPage({ locale, dictionary, path = '' }: LandingPageProps) {
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
    <main className="relative min-h-screen overflow-hidden bg-background text-text-primary">
      <LocaleLangSetter locale={locale} />
      <ViewportHeightSetter />
      <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
        <div
          className="absolute -top-40 left-1/2 h-[420px] w-[420px] -translate-x-1/2 rounded-full blur-[140px]"
          style={{ backgroundColor: 'hsla(var(--brand-gradientStart) / 0.18)' }}
        />
        <div
          className="absolute bottom-0 right-0 h-[360px] w-[360px] translate-x-1/3 translate-y-1/3 rounded-full blur-[120px]"
          style={{ backgroundColor: 'hsla(var(--brand-gradientEnd) / 0.12)' }}
        />
      </div>

      <section className="relative flex min-h-[calc(var(--hero-initial-dvh,100dvh))] w-full items-center justify-center pb-[calc(5rem+env(safe-area-inset-bottom))] pt-8 sm:pb-[calc(6rem+env(safe-area-inset-bottom))] sm:pt-12 lg:pb-[calc(7rem+env(safe-area-inset-bottom))]">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,hsla(var(--brand-gradientStart)/0.16),transparent_55%)]" />
        <div className="relative w-full max-w-4xl px-6 sm:px-0">
          <div className="relative mx-auto w-full max-w-[32rem] sm:max-w-xl">
            <div className="relative flex w-full flex-col items-center gap-8 overflow-hidden rounded-[44px] border border-border-subtle/60 bg-surface-primary/70 px-6 pb-[calc(3rem+env(safe-area-inset-bottom))] pt-12 shadow-app max-h-[760px] sm:max-h-[820px] sm:px-12">
              <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,hsla(var(--brand-gradientStart)/0.16),transparent_55%)]" />
              <div className="relative flex flex-col items-center gap-8 text-center">
                <div className="relative">
                  <div
                    className="pointer-events-none absolute inset-0 -z-10 blur-[80px] opacity-60"
                    style={{
                      background: 'radial-gradient(circle, hsla(var(--brand-gradientStart) / 0.4), hsla(var(--brand-gradientEnd) / 0.3))'
                    }}
                  />
                  <Image
                    src="/icons/tidex-wordmark.webp"
                    alt={marketing.hero.imageAlt}
                    width={280}
                    height={80}
                    priority
                    className="animate-in fade-in zoom-in-95 duration-700 drop-shadow-2xl"
                  />
                </div>
                <div className="space-y-6">
                  <h1 className="text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
                    {marketing.hero.title}
                  </h1>
                  <p className="text-pretty text-base text-text-secondary sm:text-lg">
                    {marketing.hero.description}
                  </p>
                </div>
                <div className="mx-auto grid w-full max-w-sm grid-cols-2 gap-3 sm:max-w-none sm:grid-cols-4 sm:justify-items-center">
                  {heroHighlights.map((highlight) => (
                    <span
                      key={highlight}
                      className="inline-flex h-10 w-full items-center justify-center gap-2 rounded-full border border-border-subtle/40 bg-background/60 px-4 text-sm font-medium text-text-secondary sm:h-11 sm:w-[9rem]"
                    >
                      {highlight}
                    </span>
                  ))}
                </div>
                <div className="flex w-full flex-col gap-3 sm:flex-row sm:items-center sm:justify-center">
                  <Button
                    asChild
                    className="h-12 w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-8 text-base font-semibold text-text-inverse shadow-app-lg sm:w-auto"
                  >
                    <Link href="https://app.tidex.no" target="_blank" rel="noopener noreferrer">
                      {marketing.hero.primaryCta}
                    </Link>
                  </Button>
                  <Button
                    asChild
                    variant="outline"
                    className="h-12 w-full rounded-full border-border-subtle bg-surface-primary/40 px-8 text-base font-semibold text-text-primary hover:border-brand-gradientMid hover:text-text-primary sm:w-auto"
                  >
                    <Link href="#faq">{marketing.hero.secondaryCta}</Link>
                  </Button>
                </div>
              </div>
            </div>
            <div className="mt-6 flex justify-center sm:mt-8">
              <MarketingLocaleToggle currentLocale={locale} path={path} />
            </div>
          </div>
        </div>
      </section>

      <section
        id="features"
        className="px-6 pb-20 sm:pb-24 lg:pb-28"
      >
        <div className="mx-auto w-full max-w-4xl space-y-8">
          <div className="space-y-4">
            <p className="text-sm font-medium uppercase tracking-[0.32em] text-text-muted">
              {marketing.features.eyebrow}
            </p>
            <h2 className="text-pretty text-3xl font-semibold sm:text-4xl">
              {marketing.features.heading}
            </h2>
            <p className="max-w-2xl text-pretty text-base text-text-secondary sm:text-lg">
              {marketing.features.description}
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {features.map(({ Icon, title, description }) => (
              <div
                key={title}
                className="group flex h-full flex-col gap-4 rounded-[32px] border border-border-subtle/60 bg-surface-primary/80 p-6 shadow-app transition-all duration-200 hover:-translate-y-1 hover:border-brand-gradientMid/60 hover:shadow-app-lg"
              >
                <span
                  className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-brand-gradientStart/20 via-brand-gradientMid/15 to-brand-gradientEnd/20 text-brand-gradientStart shadow-inner"
                  style={{ boxShadow: 'inset 0 1px 0 hsl(var(--brand-gradientEnd) / 0.2)' }}
                >
                  <Icon className="h-5 w-5" />
                </span>
                <div className="space-y-3">
                  <h3 className="text-lg font-semibold text-text-primary">{title}</h3>
                  <p className="text-sm text-text-secondary">{description}</p>
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
        <div className="mx-auto w-full max-w-3xl rounded-[40px] border border-border-subtle/70 bg-surface-primary/80 p-8 shadow-app-lg sm:p-12">
          <div className="mb-10 space-y-4 text-center">
            <p className="text-sm font-medium uppercase tracking-[0.32em] text-text-muted">{marketing.faq.eyebrow}</p>
            <h2 className="text-3xl font-semibold sm:text-4xl">{marketing.faq.heading}</h2>
            <p className="text-base text-text-secondary">
              {marketing.faq.description}
            </p>
          </div>

          <Accordion type="single" collapsible className="space-y-2">
            {faqs.map((faq) => (
              <AccordionItem key={faq.question} value={faq.question} className="overflow-hidden">
                <AccordionTrigger className="rounded-2xl px-4 text-left text-base sm:text-lg">
                  {faq.question}
                </AccordionTrigger>
                <AccordionContent className="px-4">
                  {faq.answers.map((paragraph, answerIndex) => (
                    <p key={`${faq.question}-${answerIndex}`} className="pb-4 text-base text-text-secondary last:pb-1">
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
        <div className="mx-auto flex w-full max-w-3xl flex-col items-center gap-6 rounded-[40px] border border-border-subtle/60 bg-surface-secondary/30 px-8 py-10 text-center shadow-app">
          <h2 className="text-3xl font-semibold sm:text-[2.5rem]">{marketing.ctaPrimary.heading}</h2>
          <p className="max-w-xl text-pretty text-base text-text-secondary sm:text-lg">
            {marketing.ctaPrimary.description}
          </p>
          <Button
            asChild
            className="h-12 rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-10 text-base font-semibold text-text-inverse shadow-app-lg"
          >
            <Link href="https://app.tidex.no" target="_blank" rel="noopener noreferrer">
              {marketing.ctaPrimary.button}
            </Link>
          </Button>
        </div>
      </section>

      <section className="px-6 pb-16 sm:pb-20">
        <div className="mx-auto flex w-full max-w-3xl flex-col items-center gap-6 rounded-[40px] border border-border-subtle/60 bg-surface-primary/80 px-8 py-10 text-center shadow-app">
          <h2 className="text-2xl font-semibold sm:text-3xl">{marketing.contact.heading}</h2>
          <p className="max-w-xl text-pretty text-base text-text-secondary">
            {marketing.contact.description}
          </p>
          <Button
            asChild
            variant="outline"
            className="h-12 rounded-full border-border-subtle bg-surface-primary px-10 text-base font-semibold text-text-primary hover:border-brand-gradientMid hover:text-text-primary"
          >
            <a href={mailtoHref}>
              {marketing.contact.button}
            </a>
          </Button>
        </div>
      </section>

      <footer className="px-6 pb-10">
        <div className="mx-auto w-full max-w-6xl space-y-3 text-center">
          <div className="flex items-center justify-center gap-3 text-sm flex-wrap">
            <Link href={payrollDocsHref} className="text-text-secondary hover:text-text-primary transition-colors font-medium">
              {marketing.footer.payrollDocs}
            </Link>
            <span className="text-text-muted">•</span>
            <Link href={privacyHref} className="text-text-secondary hover:text-text-primary transition-colors">
              {marketing.footer.privacy}
            </Link>
            <span className="text-text-muted">•</span>
            <Link href={termsHref} className="text-text-secondary hover:text-text-primary transition-colors">
              {marketing.footer.terms}
            </Link>
          </div>
          <div className="text-sm text-text-secondary">
            {marketing.footer.copyright}
          </div>
        </div>
      </footer>
    </main>
  );
}
