import { Mail, Github } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';

interface ContactPageProps {
  dictionary: DevDictionary;
}

export function ContactPage({ dictionary }: ContactPageProps) {
  const { contact } = dictionary;

  return (
    <div className="min-h-screen px-4 py-24">
      <div className="mx-auto max-w-4xl">
        {/* Header */}
        <div className="mb-16 text-center">
          <h1 className="mb-4 bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end bg-clip-text text-5xl font-bold text-transparent">
            {contact.title}
          </h1>
          <p className="text-xl text-text-secondary">{contact.subtitle}</p>
        </div>

        {/* Message */}
        <div className="mb-12 text-center">
          <p className="text-lg text-text-secondary">{contact.message}</p>
        </div>

        {/* Contact Cards */}
        <div className="grid gap-8 md:grid-cols-2">
          {/* Email Card */}
          <div className="rounded-3xl border border-border/40 bg-surface-primary/50 p-8 text-center shadow-app backdrop-blur-xs">
            <div className="mb-6 flex justify-center">
              <div className="rounded-full bg-linear-to-br from-brand-gradient-start to-brand-gradient-end p-4">
                <Mail className="h-8 w-8 text-text-inverse" />
              </div>
            </div>
            <h2 className="mb-4 text-2xl font-bold text-text-primary">{contact.email.title}</h2>
            <p className="mb-6 text-text-secondary">kristensenhjalmar2006@gmail.com</p>
            <a
              href="mailto:kristensenhjalmar2006@gmail.com"
              className="inline-flex items-center gap-2 rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-6 py-3 font-semibold text-text-inverse shadow-app transition-transform hover:scale-105"
            >
              <Mail className="h-4 w-4" />
              {contact.email.cta}
            </a>
          </div>

          {/* GitHub Card */}
          <div className="rounded-3xl border border-border/40 bg-surface-primary/50 p-8 text-center shadow-app backdrop-blur-xs">
            <div className="mb-6 flex justify-center">
              <div className="rounded-full bg-linear-to-br from-brand-gradient-start to-brand-gradient-end p-4">
                <Github className="h-8 w-8 text-text-inverse" />
              </div>
            </div>
            <h2 className="mb-4 text-2xl font-bold text-text-primary">{contact.github.title}</h2>
            <p className="mb-6 text-text-secondary">@kkarlsen06</p>
            <a
              href="https://github.com/kkarlsen06"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-full border border-border bg-surface-secondary px-6 py-3 font-semibold text-text-primary shadow-app transition-colors hover:bg-surface-primary"
            >
              <Github className="h-4 w-4" />
              {contact.github.cta}
            </a>
          </div>
        </div>

        {/* Bottom CTA */}
        <div className="mt-16 rounded-3xl border border-border/40 bg-linear-to-br from-brand-gradient-start/10 to-brand-gradient-end/10 p-12 text-center shadow-app backdrop-blur-xs">
          <h2 className="mb-4 text-3xl font-bold text-text-primary">
            {dictionary.home?.hero.cta || 'Hire Me'}
          </h2>
          <p className="mb-6 text-lg text-text-secondary">{contact.message}</p>
          <a
            href="mailto:kristensenhjalmar2006@gmail.com"
            className="inline-flex items-center gap-2 rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-8 py-4 text-lg font-semibold text-text-inverse shadow-app-lg transition-transform hover:scale-105"
          >
            <Mail className="h-5 w-5" />
            {contact.email.cta}
          </a>
        </div>
      </div>
    </div>
  );
}
