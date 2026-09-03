import Image from 'next/image';
import Link from 'next/link';
import type { CSSProperties } from 'react';
import { ArrowRight } from 'lucide-react';
import dashboardEn from '@/public/hero/dashboard-en.png';
import dashboardNo from '@/public/hero/dashboard-no.png';
import { Button } from '@/components/ui/button';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedMarketingPath } from '@/lib/paths';
import { LocaleLangSetter } from './LocaleLangSetter';
import { MarketingLocaleToggle } from './MarketingLocaleToggle';

interface LandingPageProps {
  locale: Locale;
  dictionary: Pick<Dictionary, 'marketing' | 'legal'>;
}

export function LandingPage({ locale, dictionary }: LandingPageProps) {
  const mobileBottomCtaHeight = 'calc(6.5rem + env(safe-area-inset-bottom))';
  const mobileHeroStyle = {
    '--mobile-hero-height': 'var(--hero-initial-dvh)',
    '--mobile-bottom-cta-height': mobileBottomCtaHeight,
    '--mobile-phone-fade-height': '7rem',
  } as CSSProperties;
  const marketing = dictionary.marketing;
  const faqs = marketing.faq.items;
  const privacyHref = buildLocalizedMarketingPath(locale, '/privacy');
  const termsHref = buildLocalizedMarketingPath(locale, '/terms');
  const payrollDocsHref = '/docs/payroll';
  const appStoreHref = 'https://apps.apple.com/app/id6757129790';
  const mailtoHref = `mailto:${dictionary.legal.contactEmail}?subject=${encodeURIComponent(marketing.contact.emailSubject)}&body=${encodeURIComponent(marketing.contact.emailBody)}`;
  const heroScreenshotSrc =
    locale === 'no' ? dashboardNo : dashboardEn;
  const screenAspectRatio = 1206 / 2622;
  // Model the visible black bezel, not the full chassis/glass margin.
  // Apple does not publish bezel thickness directly; using 17 Pro screen-border
  // data commonly reported around 1.44mm on all four sides.
  const screenWidthMm = 66.59;
  const screenHeightMm = 144.78;
  const visibleBezelMm = 1.44;
  const horizontalBezelRatio = visibleBezelMm / screenWidthMm;
  const verticalBezelRatio = visibleBezelMm / screenHeightMm;
  const horizontalInset = horizontalBezelRatio / (1 + horizontalBezelRatio * 2);
  const verticalInset = verticalBezelRatio / (1 + verticalBezelRatio * 2);
  const phoneOuterAspectRatio =
    (screenAspectRatio * (1 + horizontalBezelRatio * 2)) /
    (1 + verticalBezelRatio * 2);
  const phoneOuterClass = 'w-[16.8rem] sm:w-[17.2rem]';
  const phoneScreenshot = (
    wrapperClassName: string,
    phoneClassName: string,
    showAmbientGlow = true
  ) => (
    <div className={wrapperClassName}>
      {showAmbientGlow ? (
        <div className="absolute left-1/2 top-1/2 -z-10 h-[28rem] w-[28rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(56,189,248,0.18),rgba(56,189,248,0.08)_42%,transparent_72%)]" />
      ) : null}

      <div
        className={`relative inline-block overflow-hidden rounded-[3.15rem] bg-[linear-gradient(180deg,hsl(214_41%_18%)_0%,hsl(213_43%_14%)_22%,hsl(215_48%_9%)_100%)] ${phoneClassName}`}
        style={{
          aspectRatio: `${phoneOuterAspectRatio}`,
          boxShadow:
            '0 48px 120px rgba(0,0,0,0.6), inset 0 0 0 0.5px rgba(255,255,255,0.04)',
        }}
      >
        <div className="pointer-events-none absolute inset-0 rounded-[3.15rem] border border-white/10" />

        <div
          className="absolute overflow-hidden rounded-[2.9rem]"
          style={{
            left: `${horizontalInset * 100}%`,
            right: `${horizontalInset * 100}%`,
            top: `${verticalInset * 100}%`,
            bottom: `${verticalInset * 100}%`,
          }}
        >
          <img
            src={heroScreenshotSrc.src}
            alt={marketing.hero.screenshotAlt}
            className="h-full w-full object-cover"
          />
          <div
            className="pointer-events-none absolute left-1/2 z-10 -translate-x-1/2 overflow-hidden rounded-full bg-[hsl(220_54%_5%)] shadow-[0_4px_12px_rgba(0,0,0,0.26)]"
            style={{
              top: '1.15%',
              width: '34.5%',
              height: '4.3%',
            }}
          >
            <div className="absolute inset-y-1/2 right-[20%] aspect-square h-[16%] -translate-y-1/2 rounded-full bg-[rgba(10,14,20,0.78)] opacity-38" />
            <div className="absolute inset-y-1/2 right-[9%] aspect-square h-[30%] -translate-y-1/2 rounded-full bg-[radial-gradient(circle_at_35%_35%,rgba(255,255,255,0.09),rgba(74,98,132,0.1)_20%,rgba(10,14,20,0.88)_52%,rgba(0,0,0,0.96)_100%)] opacity-58" />
          </div>
          <div className="pointer-events-none absolute inset-0 rounded-[2.9rem] border border-white/12" />
        </div>
      </div>

      {showAmbientGlow ? (
        <div className="absolute bottom-0 left-1/2 -z-10 h-24 w-[78%] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,rgba(56,189,248,0.18),transparent_72%)]" />
      ) : null}
    </div>
  );

  return (
    <main
      className="relative pb-[calc(6.5rem+env(safe-area-inset-bottom))] text-text-primary lg:pb-0"
    >
      <LocaleLangSetter locale={locale} />

      <section
        className="relative flex min-h-[var(--mobile-hero-height)] flex-col overflow-hidden px-5 pb-[var(--mobile-bottom-cta-height)] pt-[max(1rem,env(safe-area-inset-top))] sm:pb-8 sm:px-8 lg:min-h-dvh lg:pb-10"
        style={mobileHeroStyle}
      >
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_130%_80%_at_50%_-15%,hsl(199_89%_48%_/_0.24),transparent_60%)]" />
          <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-background to-transparent" />
          <div className="absolute inset-x-0 top-0 h-px bg-linear-to-r from-transparent via-brand-highlight/20 to-transparent" />
        </div>

        <div className="mx-auto flex w-full max-w-6xl shrink-0 items-center justify-between py-4">
          <a
            href={appStoreHref}
            target="_blank"
            rel="noopener noreferrer"
            aria-label={marketing.hero.appStoreCta}
            className="rounded-[0.9rem] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98] sm:rounded-[1rem]"
          >
            <Image
              src="/apple-touch-icon.png"
              alt={marketing.hero.imageAlt}
              width={180}
              height={180}
              priority
              className="h-11 w-11 rounded-[0.9rem] sm:h-12 sm:w-12 sm:rounded-[1rem]"
            />
          </a>
          <MarketingLocaleToggle locale={locale} />
        </div>

        <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col lg:flex-row lg:items-center lg:gap-14 xl:gap-20">
          <div className="flex min-h-0 flex-1 flex-col py-10 sm:py-14 lg:max-w-140 lg:flex-none lg:py-0 xl:max-w-150">
            <h1 className="animate-fade-in text-balance text-[3.25rem] font-semibold leading-[1.04] tracking-[-0.05em] [animation-delay:60ms] sm:text-[3.75rem] lg:text-[4.25rem] xl:text-[4.75rem]">
              {marketing.hero.title}
            </h1>

            <p className="mt-3 max-w-[42ch] animate-fade-in text-pretty text-[1.0625rem] leading-[1.8] text-text-secondary [animation-delay:120ms] sm:text-lg lg:mb-10 xl:mb-12">
              {marketing.hero.description}
            </p>

            <div className="relative mb-2 mt-auto pt-10 animate-fade-in lg:hidden [animation-delay:150ms]">
              <div className="pointer-events-none absolute inset-0">
                <div className="absolute inset-x-0 top-0 flex justify-center">
                  <div className="h-[21rem] w-[21rem] -translate-y-[1.75rem] rounded-full bg-[radial-gradient(circle,rgba(56,189,248,0.14),rgba(56,189,248,0.06)_44%,transparent_72%)]" />
                </div>
              </div>
              <div className="relative mx-auto h-[19.5rem] w-full max-w-[21rem] overflow-visible">
                <div className="absolute inset-x-0 top-0 flex justify-center">
                  {phoneScreenshot(
                    'relative scale-[0.92] origin-top',
                    'w-[17.1rem]',
                    false
                  )}
                </div>
              </div>
            </div>

            <div className="relative z-10 hidden animate-fade-in flex-wrap items-center gap-5 [animation-delay:190ms] lg:mt-auto lg:flex lg:pt-0">
              <a
                href={appStoreHref}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center gap-2.5 whitespace-nowrap rounded-full bg-white px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_20px_rgba(255,255,255,0.1)] transition-all duration-200 hover:scale-[1.02] hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]"
              >
                <svg viewBox="0 0 24 24" fill="currentColor" className="h-[1.05rem] w-[1.05rem] shrink-0" aria-hidden="true">
                  <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701z" />
                </svg>
                {marketing.hero.appStoreCta}
              </a>
              <Link
                href="#faq"
                className="flex items-center gap-1.5 text-sm font-medium text-text-muted transition-colors hover:text-text-primary"
              >
                {marketing.hero.secondaryCta}
                <ArrowRight className="h-3.5 w-3.5" />
              </Link>
            </div>

          </div>

          <div className="hidden animate-fade-in lg:flex lg:flex-1 lg:items-center lg:justify-end [animation-delay:150ms]">
            {phoneScreenshot('relative', phoneOuterClass)}
          </div>
        </div>

        <div
          className="pointer-events-none absolute inset-x-0 bottom-0 lg:hidden"
          style={{
            height: 'calc(var(--mobile-phone-fade-height) + var(--mobile-bottom-cta-height))',
            background:
              'linear-gradient(to bottom, transparent 0, hsl(var(--background)) var(--mobile-phone-fade-height), hsl(var(--background)) 100%)',
          }}
        />
      </section>

      <div className="fixed inset-x-0 bottom-0 z-30 lg:hidden">
        <div className="pointer-events-none absolute inset-x-0 bottom-full h-12 bg-gradient-to-t from-background/90 via-background/45 to-transparent" />
        <div className="border-t border-white/8 bg-[linear-gradient(180deg,rgba(8,17,30,0.88),rgba(5,12,22,0.96))] px-5 pb-[calc(env(safe-area-inset-bottom)+0.9rem)] pt-3 shadow-[0_-18px_48px_rgba(0,0,0,0.36)] backdrop-blur-xl">
          <div className="mx-auto flex w-full max-w-6xl items-center justify-center gap-4">
            <a
              href={appStoreHref}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex h-12 items-center gap-2.5 whitespace-nowrap rounded-full bg-white px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_20px_rgba(255,255,255,0.1)] transition-all duration-200 active:scale-[0.98]"
            >
              <svg viewBox="0 0 24 24" fill="currentColor" className="h-[1.05rem] w-[1.05rem] shrink-0" aria-hidden="true">
                <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701z" />
              </svg>
              <span>{marketing.hero.appStoreCta}</span>
            </a>
            <Link
              href="#faq"
              className="flex shrink-0 items-center gap-1.5 text-sm font-medium text-text-muted transition-colors active:text-text-primary"
            >
              {marketing.hero.secondaryCta}
              <ArrowRight className="h-3.5 w-3.5" />
            </Link>
          </div>
        </div>
      </div>

      <section
        id="faq"
        className="relative overflow-hidden px-6 pt-14 pb-14 sm:pt-16 sm:pb-16 lg:pb-20"
      >
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_130%_80%_at_50%_-15%,hsl(199_89%_48%_/_0.24),transparent_60%)]" />
        </div>
        <div className="mx-auto w-full max-w-5xl">
          <div className="mb-10 max-w-2xl space-y-4 sm:mb-14 sm:space-y-5">
            <h2 className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
              {marketing.faq.heading}
            </h2>
            <p className="text-base leading-7 text-text-secondary sm:text-lg">
              {marketing.faq.description}
            </p>
          </div>

          <div className="space-y-3">
            {faqs.map((faq, index) => (
              <details
                key={faq.question}
                open={index === 0}
                className="rounded-[1.15rem] border border-white/8 bg-background/60 px-4 last:border-b sm:rounded-[1.4rem] sm:px-6"
              >
                <summary className="cursor-pointer py-5 text-left text-base font-medium text-text-primary hover:text-brand-highlight sm:py-6 sm:text-lg">
                  {faq.question}
                </summary>
                <div className="pb-5 sm:pb-6">
                  {faq.answers.map((paragraph, answerIndex) => (
                    <p
                      key={`${faq.question}-${answerIndex}`}
                      className="pb-3 text-base leading-7 text-text-secondary last:pb-0"
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

      <section className="border-y border-white/10 px-6 py-14 sm:py-16">
        <div className="mx-auto w-full max-w-5xl">
          <div className="mb-6 max-w-2xl space-y-2 sm:mb-8">
            <p className="text-xs font-medium uppercase tracking-[0.22em] text-text-muted">
              {marketing.socialProof.eyebrow}
            </p>
            <h2 className="text-balance text-2xl font-semibold tracking-[-0.03em] sm:text-3xl">
              {marketing.socialProof.heading}
            </h2>
            <p className="text-sm leading-7 text-text-secondary sm:text-base">
              {marketing.socialProof.description}
            </p>
          </div>

          <div className="grid gap-3 sm:grid-cols-3">
            {marketing.socialProof.items.map((item) => (
              <div
                key={item.title}
                className="rounded-[1.15rem] border border-white/8 bg-background/55 p-5"
              >
                <h3 className="text-base font-semibold tracking-[-0.02em]">
                  {item.title}
                </h3>
                <p className="mt-2 text-sm leading-7 text-text-secondary">
                  {item.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="px-6 pt-14 pb-20 sm:pt-16 sm:pb-28">
        <div className="mx-auto grid w-full max-w-5xl gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div className="rounded-[1.75rem] border border-white/12 bg-background/50 p-8 backdrop-blur-xl sm:p-10">
            <h2 className="max-w-lg text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
              {marketing.ctaPrimary.heading}
            </h2>
            <p className="mt-5 max-w-xl text-base leading-7 text-text-secondary sm:text-lg">
              {marketing.ctaPrimary.description}
            </p>
            <Button
              asChild
              className="mt-8 h-11 rounded-full border border-white/20 bg-white/10 px-5 text-sm font-semibold text-text-primary hover:bg-white/14"
            >
              <a href={appStoreHref} target="_blank" rel="noopener noreferrer">
                <span>{marketing.ctaPrimary.button}</span>
                <ArrowRight className="h-4 w-4" />
              </a>
            </Button>
          </div>

          <div className="rounded-[1.75rem] border border-white/12 bg-background/45 p-8 backdrop-blur-xl sm:p-10">
            <h2 className="text-2xl font-semibold tracking-[-0.03em] sm:text-[1.75rem]">
              {marketing.contact.heading}
            </h2>
            <p className="mt-5 text-sm leading-7 text-text-secondary sm:text-base">
              {marketing.contact.description}
            </p>
            <Button
              asChild
              variant="outline"
              className="mt-7 h-10 rounded-full border-white/18 bg-white/8 px-5 text-sm font-semibold text-text-primary hover:bg-white/12"
            >
              <a href={mailtoHref}>{marketing.contact.button}</a>
            </Button>
          </div>
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
          </div>
        </div>
      </footer>
    </main>
  );
}
