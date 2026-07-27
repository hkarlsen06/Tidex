import Image from 'next/image';
import { ArrowUpRight, Github } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';
import { getDevProjects } from '../lib/projects';
import { GITHUB_URL } from '../lib/contact-info';

interface AboutPageProps {
  dictionary: DevDictionary;
}

export function AboutPage({ dictionary }: AboutPageProps) {
  const { about } = dictionary;
  const skillGroups = [about.skills.frontend, about.skills.backend, about.skills.tools];
  const projects = getDevProjects(dictionary);

  return (
    <div className="px-5 pb-24 pt-32 text-text-primary sm:px-8 lg:pt-40">
      <div className="mx-auto max-w-5xl">
        <header className="mb-16 max-w-3xl">
          <span className="eyebrow">
            <span className="h-px w-6 bg-brand-highlight/60" aria-hidden />
            {about.title}
          </span>
          <h1 className="mt-5 text-[clamp(2.25rem,5.5vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.045em]">
            {about.subtitle}
          </h1>
        </header>

        {/* Portrait + bio */}
        <section className="reveal mb-20 grid gap-10 md:grid-cols-[15rem_minmax(0,1fr)] md:gap-12">
          <div>
            <div className="relative">
              <div
                className="absolute -inset-4 -z-10 rounded-full bg-[radial-gradient(circle_at_50%_40%,hsl(189_94%_52%/0.26),transparent_68%)] blur-2xl"
                aria-hidden
              />
              <Image
                src="/profile-hjalmar.webp"
                alt="Hjalmar Karlsen"
                width={512}
                height={512}
                className="aspect-square w-full max-w-[15rem] rounded-[1.5rem] border border-white/12 object-cover shadow-app"
                priority
              />
            </div>

            <div className="mt-5 flex items-center gap-2">
              {projects.map((project) => (
                <Image
                  key={project.slug}
                  src={project.icon.src}
                  alt={project.copy.title}
                  title={project.copy.title}
                  width={64}
                  height={64}
                  className="h-7 w-7 rounded-lg ring-1 ring-white/10"
                />
              ))}
            </div>
          </div>

          <div>
            <span className="eyebrow">{about.bio.label}</span>
            <p className="mt-4 text-lg leading-8 text-text-secondary">{about.bio.intro}</p>
            <p className="mt-5 text-lg leading-8 text-text-secondary">{about.bio.passion}</p>
          </div>
        </section>

        {/* Principles */}
        <section className="mb-20">
          <div className="reveal mb-8 max-w-2xl">
            <span className="eyebrow">
              <span className="h-px w-6 bg-brand-highlight/60" aria-hidden />
              {about.principles.label}
            </span>
            <h2 className="mt-4 text-[clamp(1.75rem,4vw,2.5rem)] font-semibold leading-[1.1] tracking-[-0.035em]">
              {about.principles.title}
            </h2>
          </div>

          <ol className="grid gap-5 sm:grid-cols-2">
            {about.principles.items.map((item, index) => (
              <li key={item.title} className="reveal panel p-6">
                <span className="font-mono text-xs text-brand-highlight/80">
                  {String(index + 1).padStart(2, '0')}
                </span>
                <h3 className="mt-3 text-lg font-semibold tracking-[-0.02em]">{item.title}</h3>
                <p className="mt-2 text-sm leading-6 text-text-secondary">{item.body}</p>
              </li>
            ))}
          </ol>
        </section>

        {/* Skills */}
        <section className="mb-20">
          <h2 className="reveal mb-8 text-[clamp(1.75rem,4vw,2.5rem)] font-semibold leading-[1.1] tracking-[-0.035em]">
            {about.skills.title}
          </h2>

          <dl className="reveal panel divide-y divide-white/6 overflow-hidden">
            {skillGroups.map((group) => (
              <div key={group.title} className="p-6 md:grid md:grid-cols-[13rem_minmax(0,1fr)] md:gap-10">
                <dt className="flex items-center gap-3 text-base font-semibold text-text-primary">
                  <span className="h-4 w-px bg-brand-highlight/70" aria-hidden />
                  {group.title}
                </dt>
                <dd className="mt-3 text-base leading-7 text-text-secondary md:mt-0">{group.list}</dd>
              </div>
            ))}
          </dl>
        </section>

        {/* Approach */}
        <section className="reveal panel relative overflow-hidden p-6 sm:p-10">
          <div
            className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-[radial-gradient(circle_at_center,hsl(264_85%_60%/0.24),transparent_70%)] blur-2xl"
            aria-hidden
          />
          <h2 className="relative text-2xl font-semibold tracking-[-0.025em]">{about.approach.title}</h2>
          <p className="relative mt-4 max-w-3xl text-lg leading-8 text-text-secondary">
            {about.approach.description}
          </p>
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="relative mt-8 inline-flex h-12 items-center gap-2.5 rounded-full bg-white px-5.5 text-sm font-semibold text-text-inverse shadow-[0_2px_24px_rgba(255,255,255,0.12)] transition-all duration-200 hover:shadow-[0_4px_32px_rgba(255,255,255,0.2)] active:scale-[0.98]"
          >
            <Github className="h-[1.05rem] w-[1.05rem]" />
            {about.githubCta}
            <ArrowUpRight className="h-3.5 w-3.5" />
          </a>
        </section>
      </div>
    </div>
  );
}
