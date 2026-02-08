import Image from 'next/image';
import { ExternalLink } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';

interface ProjectsPageProps {
  dictionary: DevDictionary;
}

export function ProjectsPage({ dictionary }: ProjectsPageProps) {
  const { projects } = dictionary;

  return (
    <div className="min-h-screen px-4 py-24">
      <div className="mx-auto max-w-6xl">
        {/* Header */}
        <div className="mb-16 text-center">
          <h1 className="mb-4 bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end bg-clip-text text-5xl font-bold text-transparent">
            {projects.title}
          </h1>
          <p className="text-xl text-text-secondary">{projects.subtitle}</p>
        </div>

        <div className="space-y-12">
          {/* Tidex iOS Project Card */}
          <div className="overflow-hidden rounded-3xl border border-border/40 bg-surface-primary/50 shadow-app-lg backdrop-blur-xs">
            <div className="grid gap-8 md:grid-cols-2">
              {/* Project Image/Preview */}
              <div className="flex items-center justify-center bg-linear-to-br from-brand-gradient-start/10 to-brand-gradient-end/10 p-12">
                <div className="text-center">
                  <div className="mb-6 flex justify-center">
                    <Image
                      src="/icons/tidex-app-icon.png"
                      alt="Tidex app icon"
                      width={96}
                      height={96}
                      className="rounded-[22px] shadow-app-lg"
                    />
                  </div>
                  <div className="mb-2 text-2xl font-bold text-text-primary">Tidex</div>
                  <div className="text-lg text-text-muted">{projects.tidexIos.subtitle}</div>
                </div>
              </div>

              {/* Project Details */}
              <div className="p-8">
                <h2 className="mb-4 text-3xl font-bold text-text-primary">
                  {projects.tidexIos.title}
                </h2>
                <p className="mb-6 text-text-secondary">{projects.tidexIos.description}</p>

                {/* Technologies */}
                <div className="mb-6">
                  <h3 className="mb-3 text-lg font-semibold text-text-primary">
                    {projects.tidexIos.tech}
                  </h3>
                  <div className="flex flex-wrap gap-2">
                    {['Swift', 'SwiftUI', 'Supabase', 'StoreKit 2', 'WidgetKit'].map((tech) => (
                      <span
                        key={tech}
                        className="rounded-full border border-border bg-surface-secondary px-3 py-1 text-sm text-text-secondary"
                      >
                        {tech}
                      </span>
                    ))}
                  </div>
                </div>

                {/* Features */}
                <div className="mb-6">
                  <h3 className="mb-3 text-lg font-semibold text-text-primary">
                    {projects.tidexIos.features}
                  </h3>
                  <ul className="space-y-2 text-text-secondary">
                    {[
                      projects.tidexIos.feature1,
                      projects.tidexIos.feature2,
                      projects.tidexIos.feature3,
                      projects.tidexIos.feature4,
                      projects.tidexIos.feature5,
                    ].map((feature) => (
                      <li key={feature} className="flex items-center gap-2">
                        <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-brand-gradient-mid" />
                        {feature}
                      </li>
                    ))}
                  </ul>
                </div>

                {/* Links */}
                <div className="flex flex-wrap gap-4">
                  <a
                    href="https://apps.apple.com/app/tidex/id6757129790"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-6 py-3 font-semibold text-text-inverse shadow-app transition-transform hover:scale-105"
                  >
                    <ExternalLink className="h-4 w-4" />
                    {projects.tidexIos.viewAppStore}
                  </a>
                </div>
              </div>
            </div>
          </div>

          {/* Tidex Web App Project Card */}
          <div className="overflow-hidden rounded-3xl border border-border/40 bg-surface-primary/50 shadow-app-lg backdrop-blur-xs">
            <div className="grid gap-8 md:grid-cols-2">
              {/* Project Image/Preview */}
              <div className="flex items-center justify-center bg-linear-to-br from-brand-gradient-start/10 to-brand-gradient-end/10 p-12">
                <div className="text-center">
                  <div className="mb-6 flex justify-center">
                    <Image
                      src="/icons/tidex-wordmark.webp"
                      alt="Tidex"
                      width={240}
                      height={68}
                      className="drop-shadow-2xl"
                    />
                  </div>
                  <div className="text-lg text-text-muted">{projects.tidexWeb.subtitle}</div>
                </div>
              </div>

              {/* Project Details */}
              <div className="p-8">
                <h2 className="mb-4 text-3xl font-bold text-text-primary">
                  {projects.tidexWeb.title}
                </h2>
                <p className="mb-6 text-text-secondary">{projects.tidexWeb.description}</p>

                {/* Technologies */}
                <div className="mb-6">
                  <h3 className="mb-3 text-lg font-semibold text-text-primary">
                    {projects.tidexWeb.tech}
                  </h3>
                  <div className="flex flex-wrap gap-2">
                    {['Next.js 16', 'TypeScript', 'Supabase', 'Tailwind CSS', 'React 19'].map(
                      (tech) => (
                        <span
                          key={tech}
                          className="rounded-full border border-border bg-surface-secondary px-3 py-1 text-sm text-text-secondary"
                        >
                          {tech}
                        </span>
                      )
                    )}
                  </div>
                </div>

                {/* Features */}
                <div className="mb-6">
                  <h3 className="mb-3 text-lg font-semibold text-text-primary">
                    {projects.tidexWeb.features}
                  </h3>
                  <ul className="space-y-2 text-text-secondary">
                    {[
                      projects.tidexWeb.feature1,
                      projects.tidexWeb.feature2,
                      projects.tidexWeb.feature3,
                      projects.tidexWeb.feature4,
                      projects.tidexWeb.feature5,
                    ].map((feature) => (
                      <li key={feature} className="flex items-center gap-2">
                        <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-brand-gradient-mid" />
                        {feature}
                      </li>
                    ))}
                  </ul>
                </div>

                {/* Links */}
                <div className="flex flex-wrap gap-4">
                  <a
                    href="https://app.tidex.no"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-6 py-3 font-semibold text-text-inverse shadow-app transition-transform hover:scale-105"
                  >
                    <ExternalLink className="h-4 w-4" />
                    {projects.tidexWeb.viewLive}
                  </a>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
