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
          <h1 className="mb-4 bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd bg-clip-text text-5xl font-bold text-transparent">
            {projects.title}
          </h1>
          <p className="text-xl text-text-secondary">{projects.subtitle}</p>
        </div>

        {/* Tidex Project Card */}
        <div className="overflow-hidden rounded-3xl border border-border/40 bg-surface-primary/50 shadow-app-lg backdrop-blur-sm">
          <div className="grid gap-8 md:grid-cols-2">
            {/* Project Image/Preview */}
            <div className="flex items-center justify-center bg-gradient-to-br from-brand-gradientStart/10 to-brand-gradientEnd/10 p-12">
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
                <div className="text-lg text-text-muted">Payroll Calculator & Shift Planner</div>
              </div>
            </div>

            {/* Project Details */}
            <div className="p-8">
              <h2 className="mb-4 text-3xl font-bold text-text-primary">{projects.tidex.title}</h2>
              <p className="mb-6 text-text-secondary">{projects.tidex.description}</p>

              {/* Technologies */}
              <div className="mb-6">
                <h3 className="mb-3 text-lg font-semibold text-text-primary">
                  {projects.tidex.tech}
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
                  {projects.tidex.features}
                </h3>
                <ul className="space-y-2 text-text-secondary">
                  <li className="flex items-start gap-2">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand-gradientMid" />
                    {projects.tidex.feature1}
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand-gradientMid" />
                    {projects.tidex.feature2}
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand-gradientMid" />
                    {projects.tidex.feature3}
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand-gradientMid" />
                    {projects.tidex.feature4}
                  </li>
                  <li className="flex items-start gap-2">
                    <span className="mt-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-brand-gradientMid" />
                    {projects.tidex.feature5}
                  </li>
                </ul>
              </div>

              {/* Links */}
              <div className="flex flex-wrap gap-4">
                <a
                  href="https://app.tidex.no"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-brand-gradientStart to-brand-gradientEnd px-6 py-3 font-semibold text-text-inverse shadow-app transition-transform hover:scale-105"
                >
                  <ExternalLink className="h-4 w-4" />
                  {projects.tidex.viewLive}
                </a>
              </div>
            </div>
          </div>
        </div>

        {/* Placeholder for future projects */}
        <div className="mt-12 text-center">
          <p className="text-text-muted">More projects coming soon...</p>
        </div>
      </div>
    </div>
  );
}
