import Image from 'next/image';
import { ExternalLink } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';

interface ProjectsPageProps {
  dictionary: DevDictionary;
}

export function ProjectsPage({ dictionary }: ProjectsPageProps) {
  const { projects } = dictionary;
  const projectItems = [
    {
      title: projects.tidexIos.title,
      subtitle: projects.tidexIos.subtitle,
      description: projects.tidexIos.description,
      techLabel: projects.tidexIos.tech,
      featuresLabel: projects.tidexIos.features,
      features: [
        projects.tidexIos.feature1,
        projects.tidexIos.feature2,
        projects.tidexIos.feature3,
        projects.tidexIos.feature4,
        projects.tidexIos.feature5,
      ],
      technologies: ['Swift', 'SwiftUI', 'Supabase', 'StoreKit 2', 'WidgetKit'],
      href: 'https://apps.apple.com/app/tidex/id6757129790',
      cta: projects.tidexIos.viewAppStore,
      visual: (
        <div className="flex items-center gap-5">
          <Image
            src="/icons/tidex-app-icon.png"
            alt="Tidex app icon"
            width={88}
            height={88}
            className="rounded-[1.35rem] shadow-app-lg"
          />
          <div>
            <div className="text-2xl font-semibold tracking-[-0.02em] text-text-primary">Tidex</div>
            <div className="mt-1 text-sm text-text-muted">{projects.tidexIos.subtitle}</div>
          </div>
        </div>
      ),
    },
    {
      title: projects.tidexWeb.title,
      subtitle: projects.tidexWeb.subtitle,
      description: projects.tidexWeb.description,
      techLabel: projects.tidexWeb.tech,
      featuresLabel: projects.tidexWeb.features,
      features: [
        projects.tidexWeb.feature1,
        projects.tidexWeb.feature2,
        projects.tidexWeb.feature3,
        projects.tidexWeb.feature4,
        projects.tidexWeb.feature5,
      ],
      technologies: ['Next.js 16', 'TypeScript', 'Tailwind CSS', 'React 19', 'Cloudflare Pages'],
      href: 'https://tidex.no',
      cta: projects.tidexWeb.viewLive,
      visual: (
        <div>
          <Image
            src="/icons/tidex-wordmark.webp"
            alt="Tidex"
            width={220}
            height={62}
            className="h-auto w-52"
          />
          <div className="mt-4 text-sm text-text-muted">{projects.tidexWeb.subtitle}</div>
        </div>
      ),
    },
  ];

  return (
    <div className="min-h-screen px-5 pb-20 pt-32 text-text-primary sm:px-8">
      <div className="mx-auto max-w-6xl">
        <div className="mb-14 max-w-3xl">
          <h1 className="text-balance text-[3rem] font-semibold leading-[1.06] tracking-[-0.05em] sm:text-[4rem]">
            {projects.title}
          </h1>
          <p className="mt-5 text-pretty text-lg leading-8 text-text-secondary">{projects.subtitle}</p>
        </div>

        <div className="space-y-8">
          {projectItems.map((project) => (
            <article key={project.title} className="overflow-hidden rounded-2xl border border-white/10 bg-surface-primary/64 shadow-app-lg">
              <div className="grid md:grid-cols-[22rem_1fr]">
                <div className="flex min-h-56 items-center border-b border-white/10 bg-[linear-gradient(180deg,rgba(8,17,30,0.72),rgba(5,12,22,0.88))] p-6 md:border-b-0 md:border-r md:p-8">
                  {project.visual}
                </div>

                <div className="p-6 md:p-8">
                  <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div>
                      <p className="text-sm text-text-muted">{project.subtitle}</p>
                      <h2 className="mt-2 text-3xl font-semibold tracking-[-0.03em] text-text-primary">
                        {project.title}
                      </h2>
                    </div>
                    <a
                      href={project.href}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex h-11 shrink-0 items-center gap-2 rounded-full bg-white px-4 text-sm font-semibold text-text-inverse transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]"
                    >
                      <ExternalLink className="h-4 w-4" />
                      {project.cta}
                    </a>
                  </div>

                  <p className="mt-5 max-w-3xl leading-7 text-text-secondary">{project.description}</p>

                  <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
                    <div>
                      <h3 className="text-base font-semibold text-text-primary">{project.techLabel}</h3>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {project.technologies.map((tech) => (
                        <span
                          key={tech}
                          className="rounded-lg border border-white/10 bg-surface-secondary px-2.5 py-1 text-sm text-text-secondary"
                        >
                          {tech}
                        </span>
                        ))}
                      </div>
                    </div>

                    <div>
                      <h3 className="text-base font-semibold text-text-primary">{project.featuresLabel}</h3>
                      <ul className="mt-3 space-y-2.5">
                        {project.features.map((feature) => (
                          <li key={feature} className="flex gap-3 text-sm leading-6 text-text-secondary">
                            <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-highlight/80" />
                            <span>{feature}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
            </article>
          ))}
        </div>
      </div>
    </div>
  );
}
