import Link from 'next/link';
import Image from 'next/image';
import { ArrowRight, Github, Mail } from 'lucide-react';
import type { DevLocale } from '../lib/i18n-config';
import type { DevDictionary } from '../lib/dictionaries';
import { buildLocalizedDevPath } from '../lib/paths';

interface DevLandingPageProps {
  locale: DevLocale;
  dictionary: DevDictionary;
}

export function DevLandingPage({ locale, dictionary }: DevLandingPageProps) {
  const { home } = dictionary;
  const skills = [
    {
      title: home.skills.frontend,
      items: ['Swift', 'SwiftUI', 'SwiftData', 'MVVM'],
    },
    {
      title: home.skills.backend,
      items: ['Supabase', 'PostgreSQL', 'Realtime', 'RLS'],
    },
    {
      title: home.skills.tools,
      items: ['StoreKit', 'WidgetKit', 'ActivityKit', 'watchOS'],
    },
  ];
  const profileCard = (
    <div className="rounded-2xl border border-white/10 bg-surface-primary/72 p-5 shadow-app-lg">
      <div className="flex items-center gap-4 border-b border-white/8 pb-5">
        <div className="h-18 w-18 shrink-0 overflow-hidden rounded-2xl">
          <Image
            src="/profile-hjalmar.webp"
            alt="Hjalmar Karlsen"
            width={144}
            height={144}
            className="h-full w-full scale-[1.18] object-cover"
            priority
          />
        </div>
        <div>
          <div className="text-base font-semibold text-text-primary">{home.hero.title}</div>
          <div className="mt-0.5 max-w-[24ch] text-sm leading-5 text-text-muted">{home.hero.tagline}</div>
        </div>
      </div>
      <dl className="mt-5 space-y-4">
        {skills.map((skill) => (
          <div key={skill.title}>
            <dt className="text-sm font-medium text-text-primary">{skill.title}</dt>
            <dd className="mt-2 flex flex-wrap gap-2">
              {skill.items.map((item) => (
                <span
                  key={item}
                  className="rounded-lg border border-white/10 bg-surface-secondary px-2.5 py-1 text-xs text-text-secondary"
                >
                  {item}
                </span>
              ))}
            </dd>
          </div>
        ))}
      </dl>
      <a
        href="https://github.com/TidexHQ"
        target="_blank"
        rel="noopener noreferrer"
        className="mt-6 flex h-11 items-center justify-center gap-2 rounded-xl border border-white/10 text-sm font-medium text-text-secondary transition-colors hover:border-brand-highlight/35 hover:text-text-primary"
      >
        <Github className="h-4 w-4" />
        GitHub
      </a>
    </div>
  );

  return (
    <div className="min-h-screen text-text-primary">
      <section className="relative flex min-h-[var(--hero-initial-dvh)] items-center overflow-hidden px-5 pb-16 pt-28 sm:px-8 lg:pt-20">
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_130%_80%_at_50%_-15%,hsl(199_89%_48%_/_0.24),transparent_60%)]" />
          <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-background to-transparent" />
          <div className="absolute inset-x-0 top-0 h-px bg-linear-to-r from-transparent via-brand-highlight/20 to-transparent" />
        </div>

        <div className="mx-auto grid w-full max-w-6xl gap-12 lg:grid-cols-[minmax(0,1fr)_25rem] lg:items-center lg:gap-16">
          <div className="max-w-3xl">
            <p className="mb-2 text-base leading-7 text-text-muted sm:mb-3 sm:text-lg">
              {home.hero.greeting}
            </p>
            <h1 className="text-balance text-[3.2rem] font-semibold leading-[1.04] tracking-[-0.05em] sm:text-[4.2rem] lg:text-[4.75rem]">
              {home.hero.name}
            </h1>
            <h2 className="mt-4 text-2xl font-semibold tracking-[-0.025em] text-text-primary sm:text-3xl">
              {home.hero.title}
            </h2>
            <p className="mt-5 max-w-[42ch] text-pretty text-[1.0625rem] leading-8 text-text-secondary sm:text-lg">
              {home.hero.tagline}
            </p>

            <div className="mt-10 flex flex-wrap items-center gap-5">
              <a
                href="mailto:kristensenhjalmar2006@gmail.com"
                className="inline-flex h-12 items-center gap-2.5 whitespace-nowrap rounded-full bg-white px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_20px_rgba(255,255,255,0.1)] transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]"
              >
                <Mail className="h-[1.05rem] w-[1.05rem]" />
                {home.hero.cta}
              </a>
              <Link
                href={buildLocalizedDevPath(locale, '/projects')}
                className="flex items-center gap-1.5 text-sm font-medium text-text-muted transition-colors hover:text-text-primary"
              >
                {home.hero.viewWork}
                <ArrowRight className="h-3.5 w-3.5" />
              </Link>
            </div>
          </div>

          <aside className="hidden lg:block lg:translate-y-8">
            {profileCard}
          </aside>
        </div>
      </section>

      <section className="px-5 pb-8 sm:px-8 lg:hidden">
        <div className="mx-auto w-full max-w-6xl">
          {profileCard}
        </div>
      </section>

      <section className="px-5 py-16 sm:px-8 lg:py-20">
        <div className="mx-auto w-full max-w-6xl">
          <div className="mb-10 max-w-2xl space-y-4">
            <h2 className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
              {home.skills.title}
            </h2>
            <p className="text-base leading-7 text-text-secondary sm:text-lg">
              {home.hero.tagline}
            </p>
          </div>

          <div className="grid overflow-hidden rounded-2xl border border-white/10 bg-surface-primary/58 md:grid-cols-3">
            {skills.map((skill) => (
              <div key={skill.title} className="border-white/10 p-6 md:border-l first:md:border-l-0">
                <h3 className="text-lg font-semibold text-text-primary">{skill.title}</h3>
                <ul className="mt-5 space-y-3">
                  {skill.items.map((item) => (
                    <li key={item} className="flex items-center justify-between gap-4 border-b border-white/8 pb-3 text-sm text-text-secondary last:border-b-0 last:pb-0">
                      <span>{item}</span>
                      <span className="h-1.5 w-1.5 rounded-full bg-brand-highlight/80" />
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>
      </section>

      <footer className="border-t border-white/8 px-5 py-8 sm:px-8">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-text-muted">
            © 2026 Hjalmar Karlsen. {dictionary.footer.rights}.
          </p>
          <a
            href="https://github.com/TidexHQ"
            target="_blank"
            rel="noopener noreferrer"
            className="text-text-secondary transition-colors hover:text-text-primary"
          >
            <Github className="h-5 w-5" />
          </a>
        </div>
      </footer>
    </div>
  );
}
