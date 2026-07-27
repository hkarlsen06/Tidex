import type { CSSProperties } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { ArrowRight, ArrowUpRight, Mail } from 'lucide-react';
import type { DevLocale } from '../lib/i18n-config';
import type { DevDictionary } from '../lib/dictionaries';
import { buildLocalizedDevPath } from '../lib/paths';
import { getDevProjects } from '../lib/projects';
import { EMAIL, GITHUB_URL } from '../lib/contact-info';

interface DevLandingPageProps {
  locale: DevLocale;
  dictionary: DevDictionary;
}

export function DevLandingPage({ locale, dictionary }: DevLandingPageProps) {
  const { home } = dictionary;
  const projects = getDevProjects(dictionary, locale);

  const stats = [
    { value: home.stats.productsValue, label: home.stats.productsLabel },
    { value: home.stats.storeValue, label: home.stats.storeLabel },
    { value: home.stats.platformsValue, label: home.stats.platformsLabel },
  ];

  const stack = [
    {
      title: home.skills.frontend,
      note: home.skills.frontendNote,
      items: ['Swift', 'SwiftUI', 'SwiftData', 'async/await', 'MVVM', 'Charts'],
    },
    {
      title: home.skills.backend,
      note: home.skills.backendNote,
      items: ['Supabase', 'PostgreSQL', 'Realtime', 'RLS', 'Edge Functions', 'Offline sync'],
    },
    {
      title: home.skills.tools,
      note: home.skills.toolsNote,
      items: ['StoreKit 2', 'WidgetKit', 'ActivityKit', 'watchOS', 'App Intents', 'TestFlight'],
    },
  ];

  return (
    <div className="text-text-primary">
      {/* Hero */}
      <section className="relative flex min-h-[var(--hero-initial-dvh)] items-center overflow-hidden px-5 pb-20 pt-28 sm:px-8 lg:pt-24">
        <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden>
          <div className="absolute inset-0 bg-[linear-gradient(hsl(210_40%_100%/0.035)_1px,transparent_1px),linear-gradient(90deg,hsl(210_40%_100%/0.035)_1px,transparent_1px)] bg-[size:4.5rem_4.5rem] [mask-image:radial-gradient(ellipse_75%_60%_at_50%_25%,black,transparent_75%)]" />
          <div className="absolute inset-x-0 bottom-0 h-48 bg-linear-to-t from-background to-transparent" />
        </div>

        <div className="mx-auto grid w-full max-w-6xl gap-14 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-center lg:gap-20">
          <div className="max-w-2xl">
            <p
              className="animate-fade-in text-sm font-medium uppercase tracking-[0.16em] text-text-muted"
              style={{ animationDelay: '60ms' }}
            >
              {home.hero.greeting}
            </p>

            <h1
              className="animate-fade-in mt-3 text-[clamp(2.75rem,8.5vw,5rem)] font-semibold leading-[0.98] tracking-[-0.045em]"
              style={{ animationDelay: '120ms' }}
            >
              {home.hero.name}
            </h1>

            <p
              className="animate-fade-in mt-6 max-w-[30ch] text-[clamp(1.35rem,3.4vw,2rem)] font-medium leading-[1.25] tracking-[-0.025em] text-text-primary"
              style={{ animationDelay: '180ms' }}
            >
              {home.hero.roleLead} <span className="text-gradient">{home.hero.roleAccent}</span>{' '}
              {home.hero.roleTrail}
            </p>

            <p
              className="animate-fade-in mt-6 max-w-[48ch] text-pretty text-base leading-7 text-text-secondary sm:text-[1.0625rem] sm:leading-8"
              style={{ animationDelay: '240ms' }}
            >
              {home.hero.tagline}
            </p>

            <div
              className="animate-fade-in mt-10 flex flex-wrap items-center gap-x-6 gap-y-4"
              style={{ animationDelay: '300ms' }}
            >
              <a
                href={`mailto:${EMAIL}`}
                className="inline-flex h-12 items-center gap-2.5 whitespace-nowrap rounded-full bg-white px-5.5 text-sm font-semibold text-text-inverse shadow-[0_2px_24px_rgba(255,255,255,0.12)] transition-all duration-200 hover:shadow-[0_4px_32px_rgba(255,255,255,0.2)] active:scale-[0.98]"
              >
                <Mail className="h-[1.05rem] w-[1.05rem]" />
                {home.hero.cta}
              </a>
              <Link
                href={buildLocalizedDevPath(locale, '/projects')}
                className="group inline-flex items-center gap-1.5 text-sm font-medium text-text-secondary transition-colors hover:text-text-primary"
              >
                {home.hero.viewWork}
                <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
              </Link>
            </div>

            <dl
              className="animate-fade-in mt-14 grid max-w-lg grid-cols-3 gap-px overflow-hidden rounded-xl border border-white/8 bg-white/6"
              style={{ animationDelay: '360ms' }}
            >
              {stats.map((stat) => (
                <div key={stat.label} className="bg-background/60 px-4 py-4">
                  <dt className="sr-only">{stat.label}</dt>
                  <dd>
                    <span className="block text-2xl font-semibold tracking-[-0.03em] text-text-primary">
                      {stat.value}
                    </span>
                    <span className="mt-1 block text-xs leading-4 text-text-muted">{stat.label}</span>
                  </dd>
                </div>
              ))}
            </dl>
          </div>

          <div className="animate-fade-in" style={{ animationDelay: '160ms' }}>
            <div className="relative mx-auto w-full max-w-[13.5rem] sm:max-w-[15rem] lg:max-w-none">
              <div
                className="absolute -inset-10 -z-10 rounded-[3rem] bg-[radial-gradient(circle_at_50%_40%,hsl(264_85%_62%/0.42),transparent_70%)] blur-3xl"
                aria-hidden
              />
              <div className="relative overflow-hidden rounded-[1.75rem] border border-white/12 shadow-app-lg">
                <Image
                  src="/profile-hjalmar.webp"
                  alt="Hjalmar Karlsen"
                  width={512}
                  height={512}
                  className="aspect-square w-full object-cover"
                  priority
                />
                <div
                  className="absolute inset-x-0 bottom-0 h-1/3 bg-linear-to-t from-background/80 to-transparent"
                  aria-hidden
                />
              </div>

              <div className="mt-6 flex items-center justify-center gap-3">
                {projects.map((project) => (
                  <Image
                    key={project.slug}
                    src={project.icon.src}
                    alt={project.copy.title}
                    title={project.copy.title}
                    width={64}
                    height={64}
                    className={`h-8 w-8 ${project.iconIsSquare ? 'rounded-[0.5rem]' : ''}`}
                  />
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Selected work */}
      <section className="px-5 py-20 sm:px-8 lg:py-28">
        <div className="mx-auto w-full max-w-6xl">
          <div className="reveal mb-12 flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div className="max-w-2xl">
              <span className="eyebrow">
                <span className="h-px w-6 bg-brand-highlight/60" aria-hidden />
                {home.work.label}
              </span>
              <h2 className="mt-4 text-[clamp(2rem,4.5vw,3rem)] font-semibold leading-[1.08] tracking-[-0.04em]">
                {home.work.title}
              </h2>
              <p className="mt-4 text-pretty text-base leading-7 text-text-secondary">{home.work.subtitle}</p>
            </div>
            <Link
              href={buildLocalizedDevPath(locale, '/projects')}
              className="group inline-flex shrink-0 items-center gap-1.5 text-sm font-medium text-text-secondary transition-colors hover:text-text-primary"
            >
              {home.work.all}
              <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
            </Link>
          </div>

          <div className="grid gap-5 sm:grid-cols-2">
            {projects.map((project) => (
              <a
                key={project.slug}
                href={project.links[0].href}
                target="_blank"
                rel="noopener noreferrer"
                style={{ '--project-accent': `var(${project.accent})` } as CSSProperties}
                className="reveal panel group relative flex flex-col overflow-hidden p-6 transition-colors duration-300 hover:border-[hsl(var(--project-accent)/0.4)] sm:p-7"
              >
                <div
                  className="pointer-events-none absolute -left-10 -top-10 h-48 w-48 rounded-full bg-[radial-gradient(circle_at_center,hsl(var(--project-accent)/0.45),transparent_70%)] opacity-65 blur-xl transition-opacity duration-300 group-hover:opacity-100"
                  aria-hidden
                />

                <div className="relative flex items-center gap-4">
                  <Image
                    src={project.icon.src}
                    alt=""
                    width={128}
                    height={128}
                    className={`h-14 w-14 shrink-0 ${project.iconIsSquare ? 'rounded-[0.9rem]' : ''}`}
                  />
                  <div className="min-w-0">
                    <h3 className="text-xl font-semibold tracking-[-0.025em]">{project.copy.title}</h3>
                    <span className="mt-1 block text-xs font-medium uppercase tracking-[0.1em] text-text-muted">
                      {project.copy.subtitle}
                    </span>
                  </div>
                </div>

                <p className="relative mt-5 text-sm leading-6 text-text-secondary">{project.copy.tagline}</p>

                <div className="relative mt-5 flex flex-wrap gap-1.5">
                  {project.technologies.slice(0, 4).map((tech) => (
                    <span
                      key={tech}
                      className="rounded-md border border-white/8 bg-white/[0.02] px-2 py-0.5 text-[0.7rem] font-medium text-text-muted"
                    >
                      {tech}
                    </span>
                  ))}
                </div>

                <span className="relative mt-7 inline-flex items-center gap-1.5 text-sm font-medium text-[hsl(var(--project-accent))]">
                  {project.links[0].label}
                  <ArrowUpRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                </span>
              </a>
            ))}
          </div>
        </div>
      </section>

      {/* Toolkit */}
      <section className="px-5 pb-20 sm:px-8 lg:pb-28">
        <div className="mx-auto w-full max-w-6xl">
          <div className="reveal mb-12 max-w-2xl">
            <span className="eyebrow">
              <span className="h-px w-6 bg-brand-highlight/60" aria-hidden />
              {home.skills.label}
            </span>
            <h2 className="mt-4 text-[clamp(2rem,4.5vw,3rem)] font-semibold leading-[1.08] tracking-[-0.04em]">
              {home.skills.title}
            </h2>
            <p className="mt-4 text-pretty text-base leading-7 text-text-secondary">{home.skills.subtitle}</p>
          </div>

          <div className="grid gap-5 md:grid-cols-3">
            {stack.map((group) => (
              <div key={group.title} className="reveal panel relative overflow-hidden p-6">
                <span
                  className="absolute left-6 top-0 h-[3px] w-10 rounded-b-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end"
                  aria-hidden
                />
                <h3 className="text-lg font-semibold tracking-[-0.02em]">{group.title}</h3>
                <p className="mt-2 text-sm leading-6 text-text-muted">{group.note}</p>
                <ul className="mt-5 flex flex-wrap gap-1.5">
                  {group.items.map((item) => (
                    <li
                      key={item}
                      className="rounded-md border border-white/8 bg-white/[0.02] px-2 py-1 text-xs font-medium text-text-secondary"
                    >
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Closing CTA */}
      <section className="px-5 pb-24 sm:px-8">
        <div className="mx-auto w-full max-w-6xl">
          <div className="reveal panel px-6 py-12 text-center sm:px-12 sm:py-16">
            <h2 className="mx-auto max-w-2xl text-[clamp(1.75rem,4vw,2.75rem)] font-semibold leading-[1.1] tracking-[-0.035em]">
              {home.cta.title}
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-pretty text-base leading-7 text-text-secondary">
              {home.cta.body}
            </p>
            <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
              <a
                href={`mailto:${EMAIL}`}
                className="inline-flex h-12 items-center gap-2.5 rounded-full bg-white px-5.5 text-sm font-semibold text-text-inverse shadow-[0_2px_24px_rgba(255,255,255,0.12)] transition-all duration-200 hover:shadow-[0_4px_32px_rgba(255,255,255,0.2)] active:scale-[0.98]"
              >
                <Mail className="h-[1.05rem] w-[1.05rem]" />
                {home.hero.cta}
              </a>
              <a
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center gap-2 rounded-full border border-white/12 px-5 text-sm font-medium text-text-secondary transition-colors hover:border-brand-highlight/40 hover:text-text-primary"
              >
                GitHub
                <ArrowUpRight className="h-3.5 w-3.5" />
              </a>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
