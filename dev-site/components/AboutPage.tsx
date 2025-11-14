import { Github } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';

interface AboutPageProps {
  dictionary: DevDictionary;
}

export function AboutPage({ dictionary }: AboutPageProps) {
  const { about } = dictionary;

  return (
    <div className="min-h-screen px-4 py-24">
      <div className="mx-auto max-w-4xl">
        {/* Header */}
        <div className="mb-16 text-center">
          <h1 className="mb-4 bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd bg-clip-text text-5xl font-bold text-transparent">
            {about.title}
          </h1>
          <p className="text-xl text-text-secondary">{about.subtitle}</p>
        </div>

        {/* Bio Section */}
        <section className="mb-16 rounded-3xl border border-border/40 bg-surface-primary/50 p-8 shadow-app backdrop-blur-sm md:p-12">
          <p className="mb-6 text-lg leading-relaxed text-text-secondary">{about.bio.intro}</p>
          <p className="text-lg leading-relaxed text-text-secondary">{about.bio.passion}</p>
        </section>

        {/* Skills Section */}
        <section className="mb-16">
          <h2 className="mb-8 text-center text-3xl font-bold text-text-primary">
            {about.skills.title}
          </h2>

          <div className="space-y-6">
            {/* Frontend */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-6 shadow-app backdrop-blur-sm">
              <h3 className="mb-3 text-xl font-semibold text-brand-gradientMid">
                {about.skills.frontend.title}
              </h3>
              <p className="text-text-secondary">{about.skills.frontend.list}</p>
            </div>

            {/* Backend */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-6 shadow-app backdrop-blur-sm">
              <h3 className="mb-3 text-xl font-semibold text-brand-gradientMid">
                {about.skills.backend.title}
              </h3>
              <p className="text-text-secondary">{about.skills.backend.list}</p>
            </div>

            {/* Tools */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-6 shadow-app backdrop-blur-sm">
              <h3 className="mb-3 text-xl font-semibold text-brand-gradientMid">
                {about.skills.tools.title}
              </h3>
              <p className="text-text-secondary">{about.skills.tools.list}</p>
            </div>
          </div>
        </section>

        {/* Approach Section */}
        <section className="mb-16 rounded-3xl border border-border/40 bg-gradient-to-br from-brand-gradientStart/10 to-brand-gradientEnd/10 p-8 shadow-app backdrop-blur-sm md:p-12">
          <h2 className="mb-4 text-2xl font-bold text-text-primary">{about.approach.title}</h2>
          <p className="text-lg text-text-secondary">{about.approach.description}</p>
        </section>

        {/* GitHub CTA */}
        <div className="text-center">
          <a
            href="https://github.com/kkarlsen06"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-brand-gradientStart to-brand-gradientEnd px-8 py-4 text-lg font-semibold text-text-inverse shadow-app-lg transition-transform hover:scale-105"
          >
            <Github className="h-5 w-5" />
            View my GitHub
          </a>
        </div>
      </div>
    </div>
  );
}
