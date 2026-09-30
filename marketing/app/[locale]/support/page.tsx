import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';
import { MarketingLocaleToggle } from '../../../components/MarketingLocaleToggle';
import { MarketingHomeLink } from '../../../components/MarketingHomeLink';
import { localizedPageMetadata } from '@/lib/metadata';

interface LocaleSupportPageProps {
  params: Promise<{ locale: string }>;
}

function supportCopy(locale: Locale) {
  if (locale == 'en') {
    return {
      title: 'Support',
      description: 'Contact Tidex support for help with your account or the app.',
      emailLabel: 'Email',
      responseLabel: 'Response time',
      responseValue: 'Usually within 2 business days',
      retiredTitle: 'Web app retired',
      retiredBody: 'The old Tidex web app has been retired. app.tidex.no now only exists to redirect old links and preserve Apple associated-domain support.',
      accountTitle: 'Account',
      accountBody: 'Include the email address or phone number tied to your Tidex account when you contact us. Questions about earlier purchases are handled manually by support.',
      legalTitle: 'Legal documents',
    };
  }

  return {
    title: 'Support',
    description: 'Kontakt Tidex-support for hjelp med kontoen eller appen.',
    emailLabel: 'E-post',
    responseLabel: 'Svartid',
    responseValue: 'Vanligvis innen 2 virkedager',
    retiredTitle: 'Nettappen er avviklet',
    retiredBody: 'Den gamle Tidex-nettappen er avviklet. app.tidex.no brukes nå bare til å videresende gamle lenker og bevare Apple-tilknyttede domener.',
    accountTitle: 'Konto',
    accountBody: 'Oppgi e-postadressen eller telefonnummeret som er knyttet til Tidex-kontoen din når du kontakter oss. Spørsmål om tidligere kjøp håndteres manuelt av support.',
    legalTitle: 'Juridiske dokumenter',
  };
}

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: LocaleSupportPageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const copy = supportCopy(locale as Locale);

  return localizedPageMetadata(locale as Locale, '/support', {
    title: `${copy.title} | Tidex`,
    description: copy.description,
  });
}

export default async function LocaleSupportPage({ params }: LocaleSupportPageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const typedLocale = locale as Locale;
  const dictionary = getMarketingDictionary(typedLocale);
  const copy = supportCopy(typedLocale);
  const email = dictionary.legal.contactEmail;

  return (
    <main className="min-h-screen bg-background text-text-primary">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-8 px-6 py-12">
        <div className="flex items-center justify-between gap-4">
          <MarketingHomeLink locale={typedLocale} />
          <MarketingLocaleToggle locale={typedLocale} path="/support" />
        </div>

        <div className="space-y-4">
          <h1 className="text-3xl font-semibold sm:text-4xl">{copy.title}</h1>
          <p className="max-w-2xl text-base text-text-secondary sm:text-lg">{copy.description}</p>
        </div>

        <div className="grid gap-4 rounded-xl border border-border-subtle bg-surface-primary p-6 sm:grid-cols-2">
          <div>
            <p className="text-sm font-medium text-text-muted">{copy.emailLabel}</p>
            <a className="mt-2 inline-block text-lg font-semibold hover:underline" href={`mailto:${email}`}>
              {email}
            </a>
          </div>
          <div>
            <p className="text-sm font-medium text-text-muted">{copy.responseLabel}</p>
            <p className="mt-2 text-lg font-semibold">{copy.responseValue}</p>
          </div>
        </div>

        <div className="grid gap-4 sm:grid-cols-3">
          <section className="rounded-xl border border-border-subtle bg-surface-primary p-6">
            <h2 className="text-lg font-semibold">{copy.retiredTitle}</h2>
            <p className="mt-3 text-sm leading-6 text-text-secondary">{copy.retiredBody}</p>
          </section>
          <section className="rounded-xl border border-border-subtle bg-surface-primary p-6">
            <h2 className="text-lg font-semibold">{copy.accountTitle}</h2>
            <p className="mt-3 text-sm leading-6 text-text-secondary">{copy.accountBody}</p>
          </section>
          <section className="rounded-xl border border-border-subtle bg-surface-primary p-6">
            <h2 className="text-lg font-semibold">{copy.legalTitle}</h2>
            <ul className="mt-3 space-y-2 text-sm leading-6">
              <li>
                <a className="text-text-secondary hover:text-text-primary hover:underline" href={`/${typedLocale}/privacy/`}>
                  {dictionary.marketing.footer.privacy}
                </a>
              </li>
              <li>
                <a className="text-text-secondary hover:text-text-primary hover:underline" href={`/${typedLocale}/terms/`}>
                  {dictionary.marketing.footer.terms}
                </a>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </main>
  );
}
