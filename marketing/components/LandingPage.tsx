import Image from 'next/image';
import Link from 'next/link';
import { ArrowRight, Plus } from 'lucide-react';
import tidexAppIcon from '@/public/brand/tidex-app-icon.webp';
import tidexWordmark from '@/public/brand/tidex-wordmark-dark.svg';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedMarketingPath } from '@/lib/paths';
import { HeroPhone } from './HeroPhone';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';

interface LandingPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
}

// App Store links stay in the same tab. iOS hands them to the App Store app, and some in-app
// browsers, like the ones TikTok and Instagram open, ignore taps on target="_blank" links.
const appStoreHref = 'https://apps.apple.com/app/id6757129790';

function AppStoreButton({ label, className = '' }: { label: string; className?: string }) {
  return (
    <a
      href={appStoreHref}
      className={`inline-flex h-13 items-center justify-center gap-2.5 whitespace-nowrap rounded-full bg-white px-7 text-base font-semibold text-text-inverse shadow-[0_8px_32px_rgba(76,134,234,0.35)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98] ${className}`}
    >
      <svg viewBox="0 0 24 24" fill="currentColor" className="h-5 w-5 shrink-0" aria-hidden="true">
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701z" />
      </svg>
      {label}
    </a>
  );
}

export function LandingPage({ locale, dictionary }: LandingPageProps) {
  const marketing = dictionary.marketing;
  const { hero } = marketing;
  const faqs = marketing.faq.items;
  const privacyHref = buildLocalizedMarketingPath(locale, '/privacy');
  const termsHref = buildLocalizedMarketingPath(locale, '/terms');
  const supportHref = buildLocalizedMarketingPath(locale, '/support');
  const payrollDocsHref = '/docs/payroll';
  const mailtoHref = `mailto:${dictionary.legal.contactEmail}?subject=${encodeURIComponent(marketing.contact.emailSubject)}&body=${encodeURIComponent(marketing.contact.emailBody)}`;
  // The accent word is cyan, as on the App Store screenshots and in the showcase film.
  const [titleStart, titleEnd] = hero.title.split(hero.titleEmphasis);

  return (
    <main className="relative pb-[calc(7.5rem+env(safe-area-inset-bottom))] text-text-primary lg:pb-0">
      <section className="relative overflow-hidden bg-[linear-gradient(100deg,#0a0f2e_0%,#1f1d58_100%)] px-5 pt-[max(1rem,env(safe-area-inset-top))] sm:px-8">
        <div className="pointer-events-none absolute right-[-10%] top-[35%] h-[40rem] w-[40rem] rounded-full bg-[radial-gradient(circle,#4c86ea55,transparent_65%)] lg:right-[5%] lg:top-[10%]" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-32 bg-linear-to-t from-background to-transparent" />

        <div className="relative mx-auto flex w-full max-w-6xl items-center justify-between gap-5 py-4">
          <a
            href={appStoreHref}
            aria-label={hero.logoLinkLabel}
            className="grid w-36 min-w-0 grid-cols-[90fr_325fr] items-center gap-[1.891%] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98] sm:w-[10.575rem]"
          >
            <Image src={tidexAppIcon} alt="" priority className="h-auto w-full" />
            <Image src={tidexWordmark} alt={hero.imageAlt} priority className="h-auto w-full" />
          </a>
          <MarketingLocaleToggle locale={locale} />
        </div>

        <div className="relative mx-auto grid w-full max-w-6xl items-center gap-6 lg:min-h-[calc(100dvh-5.5rem)] lg:grid-cols-[minmax(0,1fr)_24rem] lg:gap-16 xl:grid-cols-[minmax(0,1fr)_27rem]">
          <div className="pt-6 sm:pt-10 lg:pt-0">
            <h1 className="text-balance text-[2.6rem] leading-[1.08] tracking-[-0.015em] sm:text-6xl lg:text-[4.25rem] xl:text-[4.75rem]">
              {titleStart}
              <em className="not-italic text-brand-highlight">{hero.titleEmphasis}</em>
              {titleEnd}
            </h1>
            <p className="mt-4 max-w-[32ch] text-pretty text-lg leading-relaxed text-white/75 sm:text-xl">
              {hero.description}
            </p>
            <div className="mt-10 hidden flex-col items-start gap-3 lg:flex">
              <AppStoreButton label={hero.appStoreCta} />
              <p className="pl-7 text-sm text-text-muted">{hero.note}</p>
            </div>
          </div>

          <HeroPhone
            locale={locale}
            alt={hero.screenshotAlt}
            className="-mx-5 -mt-8 w-[calc(100%+2.5rem)] max-w-[26rem] drop-shadow-[0_30px_40px_rgba(4,6,26,0.6)] sm:mx-auto sm:w-full lg:mt-0 lg:h-[min(92dvh,56rem)] lg:w-auto lg:max-w-none"
          />
        </div>
      </section>

      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-white/8 bg-background/85 px-5 pb-[calc(env(safe-area-inset-bottom)+0.75rem)] pt-3 backdrop-blur-xl lg:hidden">
        <AppStoreButton label={hero.appStoreCta} className="w-full" />
        <p className="mt-2 text-center text-xs text-text-muted">{hero.note}</p>
      </div>

      <section aria-labelledby="story-heading" className="pb-14 pt-4 sm:py-20">
        <h2
          id="story-heading"
          className="mx-auto max-w-6xl px-5 text-xs font-medium uppercase tracking-[0.22em] text-brand-highlight sm:px-8"
        >
          {marketing.story.heading}
        </h2>
        {/* The other four App Store screenshots. Swipe on phones, one row on wide screens. */}
        <ul className="mx-auto mt-6 flex max-w-6xl snap-x snap-mandatory scroll-px-5 gap-3 overflow-x-auto px-5 pb-2 [scrollbar-width:none] sm:scroll-px-8 sm:px-8 lg:grid lg:grid-cols-4 lg:gap-5 lg:overflow-visible">
          {marketing.story.panels.map((panel, index) => (
            <li key={panel} className="w-[68vw] max-w-[18rem] shrink-0 snap-start lg:w-auto lg:max-w-none">
              <img
                src={`/story/${locale}/0${index + 2}.webp`}
                alt={panel}
                width={720}
                height={1564}
                loading="lazy"
                decoding="async"
                className="h-auto w-full rounded-[1.6rem]"
              />
            </li>
          ))}
        </ul>
      </section>

      <section id="faq" className="relative scroll-mt-4 px-6 py-16 sm:py-20 lg:py-24">
        <div className="mx-auto grid w-full max-w-5xl gap-10 lg:grid-cols-[minmax(0,19rem)_minmax(0,1fr)] lg:gap-16">
          <div className="lg:sticky lg:top-12 lg:self-start">
            <p className="text-xs font-medium uppercase tracking-[0.22em] text-brand-highlight">
              {marketing.faq.eyebrow}
            </p>
            <h2 className="mt-4 text-balance text-3xl tracking-[-0.015em] sm:text-4xl">
              {marketing.faq.heading}
            </h2>
            <p className="mt-4 text-base leading-7 text-text-secondary">
              {marketing.faq.description}
            </p>
            <div className="mt-8 flex flex-col items-start gap-3 text-sm font-medium">
              <Link
                href={payrollDocsHref}
                className="flex items-center gap-1.5 text-text-primary transition-colors hover:text-brand-highlight"
              >
                {marketing.faq.docsLink}
                <ArrowRight className="h-3.5 w-3.5" />
              </Link>
              <a
                href={mailtoHref}
                className="flex items-center gap-1.5 text-text-muted transition-colors hover:text-text-primary"
              >
                {marketing.faq.contactLink}
                <ArrowRight className="h-3.5 w-3.5" />
              </a>
            </div>
          </div>

          <div className="border-t border-white/10">
            {faqs.map((faq, index) => (
              <details
                key={faq.question}
                name="faq"
                open={index === 0}
                className="group border-b border-white/10"
              >
                <summary className="group/question flex cursor-pointer list-none items-start gap-4 py-5 sm:gap-6 sm:py-6 [&::-webkit-details-marker]:hidden">
                  <span className="mt-1 w-6 shrink-0 text-xs font-medium tabular-nums text-text-muted transition-colors group-open:text-brand-highlight sm:mt-1.5">
                    {String(index + 1).padStart(2, '0')}
                  </span>
                  <span className="flex-1 text-base font-medium text-text-primary transition-colors group-hover/question:text-brand-highlight sm:text-lg">
                    {faq.question}
                  </span>
                  <Plus
                    aria-hidden="true"
                    className="mt-1 h-4 w-4 shrink-0 text-text-muted transition-transform duration-200 group-open:rotate-45 group-open:text-text-primary sm:mt-1.5"
                  />
                </summary>
                <div className="space-y-3 pb-6 pl-10 pr-8 sm:pl-12">
                  {faq.answers.map((paragraph, answerIndex) => (
                    <p
                      key={`${faq.question}-${answerIndex}`}
                      className="text-base leading-7 text-text-secondary"
                    >
                      {paragraph}
                    </p>
                  ))}
                </div>
              </details>
            ))}
          </div>
        </div>
      </section>

      <section className="px-5 pb-20 pt-4 sm:px-8 sm:pb-28">
        <div className="mx-auto flex max-w-3xl flex-col items-center rounded-[2rem] bg-[linear-gradient(100deg,#1f1d58_0%,#283f99_60%,#4b72db_100%)] px-6 py-12 text-center sm:py-16">
          <Image src={tidexAppIcon} alt="" className="h-auto w-16" />
          <h2 className="mt-6 text-balance text-3xl tracking-[-0.015em] sm:text-4xl">
            {marketing.ctaPrimary.heading}
          </h2>
          <p className="mt-3 max-w-[40ch] text-pretty text-base leading-7 text-white/75">
            {marketing.ctaPrimary.description}
          </p>
          <AppStoreButton label={hero.appStoreCta} className="mt-8" />
        </div>
      </section>

      <footer className="border-t border-white/8 px-6 py-10">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="text-sm text-text-muted">{marketing.footer.copyright}</div>
          <div className="flex w-full flex-col items-start gap-2 text-sm sm:w-auto sm:flex-row sm:items-center sm:gap-6">
            <Link href={payrollDocsHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.payrollDocs}
            </Link>
            <Link href={privacyHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.privacy}
            </Link>
            <Link href={termsHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.terms}
            </Link>
            <Link href={supportHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.support}
            </Link>
          </div>
        </div>
      </footer>
    </main>
  );
}
