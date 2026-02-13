import Link from 'next/link';
import { Mail, Github } from 'lucide-react';
import type { DevLocale } from '../lib/i18n-config';
import type { DevDictionary } from '../lib/dictionaries';
import { buildLocalizedDevPath } from '../lib/paths';

interface DevLandingPageProps {
  locale: DevLocale;
  dictionary: DevDictionary;
}

export function DevLandingPage({ locale, dictionary }: DevLandingPageProps) {
  const { home } = dictionary;

  return (
    <div className="min-h-screen">
      {/* Hero Section */}
      <section className="relative flex min-h-[90vh] items-center justify-center overflow-hidden px-4 pt-16">
        {/* Background gradients */}
        <div className="absolute inset-0 -z-10">
          <div className="absolute left-1/4 top-1/4 h-96 w-96 rounded-full bg-brand-gradient-start/20 blur-[120px]" />
          <div className="absolute bottom-1/4 right-1/4 h-96 w-96 rounded-full bg-brand-gradient-end/20 blur-[120px]" />
        </div>

        <div className="mx-auto max-w-4xl text-center">
          <p className="mb-4 text-lg text-text-muted">{home.hero.greeting}</p>
          <h1 className="mb-4 bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end bg-clip-text text-6xl font-bold text-transparent md:text-7xl">
            {home.hero.name}
          </h1>
          <h2 className="mb-6 text-3xl font-semibold text-text-primary md:text-4xl">
            {home.hero.title}
          </h2>
          <p className="mb-12 text-xl text-text-secondary md:text-2xl">
            {home.hero.tagline}
          </p>

          <div className="flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <a
              href="mailto:kristensenhjalmar2006@gmail.com"
              className="inline-flex items-center gap-2 rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-8 py-4 text-lg font-semibold text-text-inverse shadow-app-lg transition-transform hover:scale-105"
            >
              <Mail className="h-5 w-5" />
              {home.hero.cta}
            </a>
            <Link
              href={buildLocalizedDevPath(locale, '/projects')}
              className="inline-flex items-center gap-2 rounded-full border border-border bg-surface-primary/50 px-8 py-4 text-lg font-semibold text-text-primary shadow-app backdrop-blur-xs transition-colors hover:bg-surface-secondary"
            >
              {home.hero.viewWork}
            </Link>
          </div>
        </div>
      </section>

      {/* Skills Section */}
      <section className="px-4 py-20">
        <div className="mx-auto max-w-6xl">
          <h2 className="mb-12 text-center text-3xl font-bold text-text-primary">
            {home.skills.title}
          </h2>

          <div className="grid gap-8 md:grid-cols-3">
            {/* Frontend */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-8 shadow-app backdrop-blur-xs">
              <h3 className="mb-4 text-xl font-semibold text-brand-gradient-mid">
                {home.skills.frontend}
              </h3>
              <ul className="space-y-2 text-text-secondary">
                <li>React & Next.js</li>
                <li>TypeScript</li>
                <li>Tailwind CSS</li>
                <li>Responsive Design</li>
              </ul>
            </div>

            {/* Backend */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-8 shadow-app backdrop-blur-xs">
              <h3 className="mb-4 text-xl font-semibold text-brand-gradient-mid">
                {home.skills.backend}
              </h3>
              <ul className="space-y-2 text-text-secondary">
                <li>Node.js</li>
                <li>Supabase</li>
                <li>PostgreSQL</li>
                <li>RESTful APIs</li>
              </ul>
            </div>

            {/* Tools */}
            <div className="rounded-2xl border border-border/40 bg-surface-primary/50 p-8 shadow-app backdrop-blur-xs">
              <h3 className="mb-4 text-xl font-semibold text-brand-gradient-mid">
                {home.skills.tools}
              </h3>
              <ul className="space-y-2 text-text-secondary">
                <li>Git & GitHub</li>
                <li>Vercel</li>
                <li>ESLint</li>
                <li>Modern Workflow</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border/40 px-4 py-8">
        <div className="mx-auto flex max-w-6xl items-center justify-between">
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
