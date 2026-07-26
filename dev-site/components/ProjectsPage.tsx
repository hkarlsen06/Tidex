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
      copy: projects.tidex,
      icon: { src: '/icons/tidex-app-icon.png', alt: 'Tidex app icon' },
      technologies: ['Swift', 'SwiftUI', 'SwiftData', 'Supabase', 'StoreKit 2', 'WidgetKit', 'ActivityKit', 'watchOS', 'Next.js'],
      links: [
        { href: 'https://apps.apple.com/app/tidex/id6757129790', label: projects.ctaAppStore },
        { href: 'https://tidex.no', label: `${projects.ctaVisit} tidex.no` },
      ],
    },
    {
      copy: projects.paeonia,
      icon: { src: '/icons/paeonia-app-icon.png', alt: 'Paeonia app icon' },
      technologies: ['Swift', 'SwiftUI', 'SwiftData', 'Supabase', 'StoreKit 2', 'WidgetKit', 'Next.js'],
      links: [
        { href: 'https://apps.apple.com/app/paeonia/id6779833892', label: projects.ctaAppStore },
        { href: 'https://paeonia.no', label: `${projects.ctaVisit} paeonia.no` },
      ],
    },
    {
      copy: projects.kvist,
      icon: { src: '/icons/kvist-app-icon.png', alt: 'Kvist app icon' },
      technologies: ['Swift', 'SwiftUI', 'macOS', 'Swift Package Manager', 'Git'],
      links: [{ href: 'https://github.com/kkarlsen06/Kvist', label: projects.ctaSource }],
    },
    {
      copy: projects.lyriclint,
      icon: { src: '/icons/lyriclint-app-icon.svg', alt: 'LyricLint app icon' },
      technologies: ['SvelteKit', 'Svelte 5', 'TypeScript', 'CodeMirror 6', 'IndexedDB', 'Playwright'],
      links: [
        { href: 'https://lyriclint.com', label: `${projects.ctaVisit} lyriclint.com` },
        { href: 'https://github.com/kkarlsen06/LyricLint_for_Genius', label: projects.ctaSource },
      ],
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
          {projectItems.map((project) => {
            const { copy } = project;
            const features = [
              copy.feature1,
              copy.feature2,
              copy.feature3,
              copy.feature4,
              copy.feature5,
              copy.feature6,
            ];

            return (
              <article key={copy.title} className="overflow-hidden rounded-2xl border border-white/10 bg-surface-primary/64 shadow-app-lg">
                <div className="grid md:grid-cols-[22rem_1fr]">
                  <div className="flex min-h-56 items-center border-b border-white/10 bg-[linear-gradient(180deg,rgba(8,17,30,0.72),rgba(5,12,22,0.88))] p-6 md:border-b-0 md:border-r md:p-8">
                    <div className="flex items-center gap-5">
                      <Image
                        src={project.icon.src}
                        alt={project.icon.alt}
                        width={88}
                        height={88}
                        className="h-22 w-22 rounded-[1.35rem] shadow-app-lg"
                      />
                      <div>
                        <div className="text-2xl font-semibold tracking-[-0.02em] text-text-primary">{copy.title}</div>
                        <div className="mt-1 text-sm text-text-muted">{copy.subtitle}</div>
                      </div>
                    </div>
                  </div>

                  <div className="p-6 md:p-8">
                    <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                      <div>
                        <p className="text-sm text-text-muted">{copy.subtitle}</p>
                        <h2 className="mt-2 text-3xl font-semibold tracking-[-0.03em] text-text-primary">
                          {copy.title}
                        </h2>
                      </div>
                      <div className="flex flex-wrap gap-2.5">
                        {project.links.map((link, index) => (
                          <a
                            key={link.href}
                            href={link.href}
                            target="_blank"
                            rel="noopener noreferrer"
                            className={
                              index === 0
                                ? 'inline-flex h-11 shrink-0 items-center gap-2 rounded-full bg-white px-4 text-sm font-semibold text-text-inverse transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]'
                                : 'inline-flex h-11 shrink-0 items-center gap-2 rounded-full border border-white/12 px-4 text-sm font-medium text-text-secondary transition-colors hover:border-brand-highlight/35 hover:text-text-primary'
                            }
                          >
                            <ExternalLink className="h-4 w-4" />
                            {link.label}
                          </a>
                        ))}
                      </div>
                    </div>

                    <p className="mt-5 max-w-3xl leading-7 text-text-secondary">{copy.description}</p>

                    <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
                      <div>
                        <h3 className="text-base font-semibold text-text-primary">{projects.techLabel}</h3>
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
                        <h3 className="text-base font-semibold text-text-primary">{projects.featuresLabel}</h3>
                        <ul className="mt-3 space-y-2.5">
                          {features.map((feature) => (
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
            );
          })}
        </div>
      </div>
    </div>
  );
}
