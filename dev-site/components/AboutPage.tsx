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
          <h1 className="mb-4 bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end bg-clip-text text-5xl font-bold text-transparent">
            {about.title}
          </h1>
          <p className="text-xl text-text-secondary">{about.subtitle}</p>
        </div>

        {/* Bio Section */}
        <section className="mb-16 rounded-3xl border border-border/40 bg-surface-primary/50 p-8 shadow-app backdrop-blur-xs md:p-12">
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
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-6 shadow-app backdrop-blur-xs">
              <h3 className="mb-3 text-xl font-semibold text-brand-gradient-mid">
                {about.skills.frontend.title}
              </h3>
              <p className="text-text-secondary">{about.skills.frontend.list}</p>
            </div>

            {/* Backend */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-6 shadow-app backdrop-blur-xs">
              <h3 className="mb-3 text-xl font-semibold text-brand-gradient-mid">
                {about.skills.backend.title}
              </h3>
              <p className="text-text-secondary">{about.skills.backend.list}</p>
            </div>

            {/* Tools */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-6 shadow-app backdrop-blur-xs">
              <h3 className="mb-3 text-xl font-semibold text-brand-gradient-mid">
                {about.skills.tools.title}
              </h3>
              <p className="text-text-secondary">{about.skills.tools.list}</p>
            </div>
          </div>
        </section>

        {/* Approach Section */}
        <section className="mb-16 rounded-3xl border border-border/40 bg-linear-to-br from-brand-gradient-start/10 to-brand-gradient-end/10 p-8 shadow-app backdrop-blur-xs md:p-12">
          <h2 className="mb-4 text-2xl font-bold text-text-primary">{about.approach.title}</h2>
          <p className="text-lg text-text-secondary">{about.approach.description}</p>
        </section>

        {/* GitHub CTA */}
        <div className="text-center">
          <a
            href="https://github.com/TidexHQ"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-8 py-4 text-lg font-semibold text-text-inverse shadow-app-lg transition-transform hover:scale-105"
          >
            <Github className="h-5 w-5" />
            View my GitHub
          </a>
        </div>
      </div>
    </div>
  );
}
