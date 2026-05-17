import { Mail, Github } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';

interface ContactPageProps {
  dictionary: DevDictionary;
}

export function ContactPage({ dictionary }: ContactPageProps) {
  const { contact } = dictionary;

  return (
    <div className="min-h-screen px-5 pb-20 pt-32 text-text-primary sm:px-8">
      <div className="mx-auto max-w-5xl">
        <div className="mb-14 max-w-3xl">
          <h1 className="text-balance text-[3rem] font-semibold leading-[1.06] tracking-[-0.05em] sm:text-[4rem]">
            {contact.title}
          </h1>
          <p className="mt-5 text-pretty text-lg leading-8 text-text-secondary">{contact.subtitle}</p>
        </div>

        <div className="grid gap-6 md:grid-cols-2">
          <div className="rounded-2xl border border-white/10 bg-surface-primary/64 p-6 shadow-app md:p-8">
            <div className="mb-6 flex h-12 w-12 items-center justify-center rounded-xl border border-white/10 bg-surface-secondary">
              <Mail className="h-5 w-5 text-brand-highlight" />
            </div>
            <h2 className="text-2xl font-semibold tracking-[-0.02em] text-text-primary">{contact.email.title}</h2>
            <p className="mt-3 text-text-secondary">kristensenhjalmar2006@gmail.com</p>
            <a
              href="mailto:kristensenhjalmar2006@gmail.com"
              className="mt-8 inline-flex h-11 items-center gap-2 rounded-full bg-white px-4 text-sm font-semibold text-text-inverse transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]"
            >
              <Mail className="h-4 w-4" />
              {contact.email.cta}
            </a>
          </div>

          <div className="rounded-2xl border border-white/10 bg-surface-primary/64 p-6 shadow-app md:p-8">
            <div className="mb-6 flex h-12 w-12 items-center justify-center rounded-xl border border-white/10 bg-surface-secondary">
              <Github className="h-5 w-5 text-brand-highlight" />
            </div>
            <h2 className="text-2xl font-semibold tracking-[-0.02em] text-text-primary">{contact.github.title}</h2>
            <p className="mt-3 text-text-secondary">@kkarlsen06</p>
            <a
              href="https://github.com/TidexHQ"
              target="_blank"
              rel="noopener noreferrer"
              className="mt-8 inline-flex h-11 items-center gap-2 rounded-full border border-white/10 px-4 text-sm font-semibold text-text-primary transition-colors hover:border-brand-highlight/35"
            >
              <Github className="h-4 w-4" />
              {contact.github.cta}
            </a>
          </div>
        </div>

        <div className="mt-8 rounded-2xl border border-brand-highlight/18 bg-[linear-gradient(180deg,rgba(8,17,30,0.74),rgba(5,12,22,0.9))] p-6 md:p-8">
          <h2 className="text-2xl font-semibold tracking-[-0.02em] text-text-primary">
            {dictionary.home?.hero.cta || 'Hire Me'}
          </h2>
          <p className="mt-4 max-w-2xl text-lg leading-8 text-text-secondary">{contact.message}</p>
          <a
            href="mailto:kristensenhjalmar2006@gmail.com"
            className="mt-8 inline-flex h-12 items-center gap-2.5 rounded-full bg-white px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_20px_rgba(255,255,255,0.1)] transition-all duration-200 hover:shadow-[0_4px_30px_rgba(255,255,255,0.18)] active:scale-[0.98]"
          >
            <Mail className="h-[1.05rem] w-[1.05rem]" />
            {contact.email.cta}
          </a>
        </div>
      </div>
    </div>
  );
}
