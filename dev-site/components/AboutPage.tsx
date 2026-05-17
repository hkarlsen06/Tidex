import { Github } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';

interface AboutPageProps {
  dictionary: DevDictionary;
}

export function AboutPage({ dictionary }: AboutPageProps) {
  const { about } = dictionary;
  const skillGroups = [
    about.skills.frontend,
    about.skills.backend,
    about.skills.tools,
  ];

  return (
    <div className="min-h-screen px-5 pb-20 pt-32 text-text-primary sm:px-8">
      <div className="mx-auto max-w-5xl">
        <div className="mb-14 max-w-3xl">
          <h1 className="text-balance text-[3rem] font-semibold leading-[1.06] tracking-[-0.05em] sm:text-[4rem]">
            {about.title}
          </h1>
          <p className="mt-5 text-pretty text-lg leading-8 text-text-secondary">{about.subtitle}</p>
        </div>

        <section className="mb-12 rounded-2xl border border-white/10 bg-surface-primary/64 p-6 shadow-app md:p-8">
          <p className="text-lg leading-8 text-text-secondary">{about.bio.intro}</p>
          <p className="mt-6 text-lg leading-8 text-text-secondary">{about.bio.passion}</p>
        </section>

        <section className="mb-12">
          <h2 className="mb-6 text-3xl font-semibold tracking-[-0.03em] text-text-primary">
            {about.skills.title}
          </h2>

          <div className="grid overflow-hidden rounded-2xl border border-white/10 bg-surface-primary/58">
            {skillGroups.map((group) => (
              <div key={group.title} className="border-b border-white/10 p-6 last:border-b-0 md:grid md:grid-cols-[12rem_1fr] md:gap-8">
                <h3 className="text-lg font-semibold text-text-primary">{group.title}</h3>
                <p className="mt-3 leading-7 text-text-secondary md:mt-0">{group.list}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="mb-12 rounded-2xl border border-brand-highlight/18 bg-[linear-gradient(180deg,rgba(8,17,30,0.74),rgba(5,12,22,0.9))] p-6 md:p-8">
          <h2 className="text-2xl font-semibold tracking-[-0.02em] text-text-primary">{about.approach.title}</h2>
          <p className="mt-4 max-w-3xl text-lg leading-8 text-text-secondary">{about.approach.description}</p>
        </section>

        <div>
          <a
            href="https://github.com/TidexHQ"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex h-12 items-center gap-2.5 rounded-full bg-white px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_20px_rgba(255,255,255,0.1)] transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]"
          >
            <Github className="h-[1.05rem] w-[1.05rem]" />
            View my GitHub
          </a>
        </div>
      </div>
    </div>
  );
}
