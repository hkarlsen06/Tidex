import { ArrowUpRight, Github, Mail } from 'lucide-react';
import type { DevDictionary } from '../lib/dictionaries';
import { EMAIL, GITHUB_HANDLE, GITHUB_ORG_HANDLE, GITHUB_ORG_URL, GITHUB_URL } from '../lib/contact-info';

interface ContactPageProps {
  dictionary: DevDictionary;
}

export function ContactPage({ dictionary }: ContactPageProps) {
  const { contact } = dictionary;

  const channels = [
    {
      icon: Mail,
      title: contact.email.title,
      value: EMAIL,
      href: `mailto:${EMAIL}`,
      cta: contact.email.cta,
      external: false,
    },
    {
      icon: Github,
      title: contact.github.title,
      value: `@${GITHUB_HANDLE}`,
      href: GITHUB_URL,
      cta: contact.github.cta,
      external: true,
    },
  ];

  return (
    <div className="px-5 pb-24 pt-32 text-text-primary sm:px-8 lg:pt-40">
      <div className="mx-auto max-w-5xl">
        <header className="mb-16 max-w-3xl">
          <span className="eyebrow">
            <span className="h-px w-6 bg-brand-highlight/60" aria-hidden />
            {contact.label}
          </span>
          <h1 className="mt-5 text-[clamp(2.25rem,5.5vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.045em]">
            {contact.title}
          </h1>
          <p className="mt-5 text-pretty text-lg leading-8 text-text-secondary">{contact.subtitle}</p>
        </header>

        <div className="reveal panel relative overflow-hidden px-6 py-10 sm:px-10 sm:py-14">
          <div
            className="pointer-events-none absolute inset-x-0 -top-32 h-72 bg-[radial-gradient(ellipse_55%_100%_at_30%_100%,hsl(189_94%_52%/0.2),transparent_70%)]"
            aria-hidden
          />
          <div
            className="pointer-events-none absolute inset-x-0 -bottom-32 h-72 bg-[radial-gradient(ellipse_50%_100%_at_75%_0%,hsl(264_85%_60%/0.22),transparent_70%)]"
            aria-hidden
          />

          <h2 className="relative max-w-xl text-[clamp(1.6rem,3.6vw,2.35rem)] font-semibold leading-[1.15] tracking-[-0.035em]">
            {contact.hire.title}
          </h2>
          <p className="relative mt-4 max-w-2xl text-base leading-7 text-text-secondary sm:text-lg sm:leading-8">
            {contact.message}
          </p>

          <a
            href={`mailto:${EMAIL}`}
            className="relative mt-9 inline-flex h-12 items-center gap-2.5 rounded-full bg-white px-5.5 text-sm font-semibold text-text-inverse shadow-[0_2px_24px_rgba(255,255,255,0.12)] transition-all duration-200 hover:shadow-[0_4px_32px_rgba(255,255,255,0.2)] active:scale-[0.98]"
          >
            <Mail className="h-[1.05rem] w-[1.05rem]" />
            {contact.email.cta}
          </a>
        </div>

        <div className="mt-6 grid gap-5 md:grid-cols-2">
          {channels.map((channel) => (
            <a
              key={channel.title}
              href={channel.href}
              {...(channel.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
              className="reveal panel group flex items-center gap-4 p-6 transition-colors hover:border-brand-highlight/35"
            >
              <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-white/10 bg-white/[0.03] text-brand-highlight">
                <channel.icon className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-semibold text-text-primary">{channel.title}</span>
                <span className="mt-0.5 block truncate text-sm text-text-muted">{channel.value}</span>
              </span>
              <ArrowUpRight className="h-4 w-4 shrink-0 text-text-muted transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
            </a>
          ))}
        </div>

        <p className="mt-8 text-sm text-text-muted">
          {contact.orgLabel}{' '}
          <a
            href={GITHUB_ORG_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="text-text-secondary underline decoration-white/20 underline-offset-4 transition-colors hover:text-text-primary hover:decoration-brand-highlight/50"
          >
            @{GITHUB_ORG_HANDLE}
          </a>
        </p>
      </div>
    </div>
  );
}
