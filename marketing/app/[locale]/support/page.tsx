import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';
import { MarketingLocaleToggle } from '../../../components/MarketingLocaleToggle';
import { LocaleLangSetter } from '../../../components/LocaleLangSetter';

interface LocaleSupportPageProps {
  params: Promise<{ locale: string }>;
}

function supportCopy(locale: Locale) {
  if (locale == 'en') {
    return {
      title: 'Support',
      description: 'Contact Tidex support for help with your account, subscriptions, billing, or app issues.',
      emailLabel: 'Email',
      responseLabel: 'Response time',
      responseValue: 'Usually within 2 business days',
      accountTitle: 'Account and billing',
      accountBody: 'Include the email address or phone number tied to your Tidex account when you contact us.',
      legalTitle: 'Legal documents',
      legalBody: 'Privacy Policy and Terms of Service are available on the marketing site.',
    };
  }

  return {
    title: 'Support',
    description: 'Kontakt Tidex-support for hjelp med konto, abonnement, betaling eller problemer i appen.',
    emailLabel: 'E-post',
    responseLabel: 'Svartid',
    responseValue: 'Vanligvis innen 2 virkedager',
    accountTitle: 'Konto og betaling',
    accountBody: 'Oppgi e-postadressen eller telefonnummeret som er knyttet til Tidex-kontoen din når du kontakter oss.',
    legalTitle: 'Juridiske dokumenter',
    legalBody: 'Personvernerklæring og vilkår for bruk finnes på markedsnettstedet.',
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
  const url = `https://tidex.no/${locale}/support`;

  return {
    title: `${copy.title} - Tidex`,
    description: copy.description,
    openGraph: {
      title: `${copy.title} - Tidex`,
      description: copy.description,
      url,
      type: 'website',
    },
  };
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
      <LocaleLangSetter locale={typedLocale} />
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-8 px-6 py-12">
        <div className="flex items-center justify-end">
          <MarketingLocaleToggle />
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

        <div className="grid gap-4 sm:grid-cols-2">
          <section className="rounded-xl border border-border-subtle bg-surface-primary p-6">
            <h2 className="text-lg font-semibold">{copy.accountTitle}</h2>
            <p className="mt-3 text-sm leading-6 text-text-secondary">{copy.accountBody}</p>
          </section>
          <section className="rounded-xl border border-border-subtle bg-surface-primary p-6">
            <h2 className="text-lg font-semibold">{copy.legalTitle}</h2>
            <p className="mt-3 text-sm leading-6 text-text-secondary">{copy.legalBody}</p>
          </section>
        </div>
      </div>
    </main>
  );
}
