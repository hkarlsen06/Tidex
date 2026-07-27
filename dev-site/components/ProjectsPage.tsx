import type { CSSProperties } from 'react';
import Image from 'next/image';
import { ArrowUpRight, Check } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';
import type { DevLocale } from '../lib/i18n-config';
import { getDevProjects, projectFeatures } from '../lib/projects';

interface ProjectsPageProps {
  locale: DevLocale;
  dictionary: DevDictionary;
}

export function ProjectsPage({ locale, dictionary }: ProjectsPageProps) {
  const { projects } = dictionary;
  const projectItems = getDevProjects(dictionary, locale);

  return (
    <div className="px-5 pb-24 pt-32 text-text-primary sm:px-8 lg:pt-40">
      <div className="mx-auto max-w-6xl">
        <header className="mb-16 max-w-3xl">
          <span className="eyebrow">
            <span className="h-px w-6 bg-brand-highlight/60" aria-hidden />
            {projects.title}
          </span>
          <h1 className="mt-5 text-[clamp(2.25rem,5.5vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.045em]">
            {projects.subtitle}
          </h1>
        </header>

        <div className="space-y-6">
          {projectItems.map((project, index) => {
            const { copy } = project;

            return (
              <article
                key={project.slug}
                id={project.slug}
                style={{ '--project-accent': `var(${project.accent})` } as CSSProperties}
                className="reveal panel relative overflow-hidden scroll-mt-24"
              >
                <span
                  className="absolute left-6 top-0 h-[3px] w-12 rounded-b-full bg-[hsl(var(--project-accent))] sm:left-8 lg:left-10"
                  aria-hidden
                />
                <div
                  className="pointer-events-none absolute -left-16 -top-16 h-72 w-72 rounded-full bg-[radial-gradient(circle_at_center,hsl(var(--project-accent)/0.28),transparent_70%)] blur-2xl"
                  aria-hidden
                />

                <div className="relative p-6 sm:p-8 lg:p-10">
                  <div className="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
                    <div className="flex items-start gap-5">
                      <Image
                        src={project.icon.src}
                        alt=""
                        width={176}
                        height={176}
                        className={`h-16 w-16 shrink-0 sm:h-20 sm:w-20 ${
                          project.iconIsSquare ? 'rounded-[1rem] sm:rounded-[1.25rem]' : ''
                        }`}
                      />
                      <div>
                        <div className="flex items-center gap-3">
                          <span className="font-mono text-xs text-text-muted">
                            {String(index + 1).padStart(2, '0')}
                          </span>
                          <span className="rounded-full border border-white/10 bg-white/[0.03] px-2.5 py-0.5 text-xs font-medium text-text-muted">
                            {copy.subtitle}
                          </span>
                        </div>
                        <h2 className="mt-2 text-3xl font-semibold tracking-[-0.035em] sm:text-4xl">
                          {copy.title}
                        </h2>
                        <p className="mt-2 max-w-md text-sm leading-6 text-[hsl(var(--project-accent))]">
                          {copy.tagline}
                        </p>
                      </div>
                    </div>

                    <div className="flex flex-wrap gap-2.5">
                      {project.links.map((link, linkIndex) => (
                        <a
                          key={link.href}
                          href={link.href}
                          target="_blank"
                          rel="noopener noreferrer"
                          className={
                            linkIndex === 0
                              ? 'inline-flex h-11 shrink-0 items-center gap-2 rounded-full bg-white px-4.5 text-sm font-semibold text-text-inverse transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.2)] active:scale-[0.98]'
                              : 'inline-flex h-11 shrink-0 items-center gap-2 rounded-full border border-white/12 px-4.5 text-sm font-medium text-text-secondary transition-colors hover:border-[hsl(var(--project-accent)/0.5)] hover:text-text-primary'
                          }
                        >
                          {link.label}
                          <ArrowUpRight className="h-3.5 w-3.5" />
                        </a>
                      ))}
                    </div>
                  </div>

                  <p className="mt-8 max-w-3xl text-base leading-7 text-text-secondary">{copy.description}</p>

                  <div className="mt-9 grid gap-8 border-t border-white/6 pt-8 lg:grid-cols-[minmax(0,17rem)_minmax(0,1fr)] lg:gap-12">
                    <div>
                      <h3 className="eyebrow">{projects.techLabel}</h3>
                      <div className="mt-4 flex flex-wrap gap-1.5">
                        {project.technologies.map((tech) => (
                          <span
                            key={tech}
                            className="rounded-md border border-white/8 bg-white/[0.02] px-2 py-1 text-xs font-medium text-text-secondary"
                          >
                            {tech}
                          </span>
                        ))}
                      </div>
                    </div>

                    <div>
                      <h3 className="eyebrow">{projects.featuresLabel}</h3>
                      <ul className="mt-4 grid gap-x-8 gap-y-2.5 sm:grid-cols-2">
                        {projectFeatures(copy).map((feature) => (
                          <li key={feature} className="flex gap-2.5 text-sm leading-6 text-text-secondary">
                            <Check
                              className="mt-1 h-3.5 w-3.5 shrink-0 text-[hsl(var(--project-accent))]"
                              aria-hidden
                            />
                            <span>{feature}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      </div>
    </div>
  );
}
