import type { Metadata } from 'next';
import Image from 'next/image';
import { AppStoreButton } from '@/components/LandingPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import tidexWordmark from '@/public/brand/tidex-wordmark-dark.svg';

// _redirects serves this page for every /invite/<user id>. The app opens those links itself
// when it is installed, so only people without the app see it. One path cannot carry a locale,
// so the page has Norwegian and English, like the 404 page.
export const metadata: Metadata = {
  title: 'Invitasjon til Tidex | Invitation to Tidex',
  description: 'Last ned Tidex og åpne lenken på nytt for å koble til. Get Tidex and open the link again to connect.',
  robots: { index: false },
};

const copy = {
  no: {
    title: 'Du er invitert til Tidex',
    body: 'En venn vil koble seg til deg på Tidex, så dere kan se vaktene til hverandre. Ingenting deles før du bekrefter det i appen.',
    next: 'Når du har installert Tidex, åpner du lenken du fikk på nytt.',
  },
  en: {
    title: 'You are invited to Tidex',
    body: 'A friend wants to connect with you on Tidex, so you can see each other\'s shifts. Nothing is shared until you confirm it in the app.',
    next: 'Once you have installed Tidex, open the link you got again.',
  },
} as const;

export default function InvitePage() {
  return (
    <main className="flex min-h-screen flex-col items-center px-6 pb-16 pt-[max(2rem,env(safe-area-inset-top))] text-center text-text-primary">
      <a href="/" className="inline-flex items-center">
        <Image src={tidexWordmark} alt="Tidex" priority className="h-7 w-auto" />
      </a>
      <div className="flex w-full max-w-md flex-1 flex-col justify-center gap-12 py-12">
        {(['no', 'en'] as const).map((locale) => {
          const Heading = locale === 'no' ? 'h1' : 'h2';
          return (
          <section key={locale} lang={locale} className="flex flex-col items-center gap-5">
            <Heading className="text-balance text-3xl font-semibold sm:text-4xl">{copy[locale].title}</Heading>
            <p className="text-pretty text-base leading-7 text-text-secondary">{copy[locale].body}</p>
            <AppStoreButton label={getMarketingDictionary(locale).marketing.hero.appStoreCta} />
            <p className="text-pretty text-sm leading-6 text-text-muted">{copy[locale].next}</p>
          </section>
          );
        })}
      </div>
    </main>
  );
}
