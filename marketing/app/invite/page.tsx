import type { Metadata } from 'next';
import Image from 'next/image';
import { AppStoreButton } from '@/components/LandingPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import tidexWordmark from '@/public/brand/tidex-wordmark-dark.svg';
import { OpenInAppLink } from './OpenInAppLink';

// _redirects serves this page for every /invite/<user id>. The app opens those links itself
// when it is installed, except from Safari's address bar, so this page also opens the app.
// One path cannot carry a locale, so the page has Norwegian and English, like the 404 page.
export const metadata: Metadata = {
  title: 'Invitasjon til Tidex | Invitation to Tidex',
  description: 'Last ned Tidex og åpne invitasjonen i appen. Get Tidex and open the invite in the app.',
  robots: { index: false },
};

const copy = {
  no: {
    title: 'Du er invitert til Tidex',
    body: 'En venn vil koble seg til deg på Tidex, så dere kan se vaktene til hverandre. Ingenting deles før du bekrefter det i appen.',
    next: 'Har du Tidex allerede, trykker du Åpne i Tidex. Har du nettopp installert appen, kommer du tilbake hit og gjør det samme.',
    open: 'Åpne i Tidex',
  },
  en: {
    title: 'You are invited to Tidex',
    body: 'A friend wants to connect with you on Tidex, so you can see each other\'s shifts. Nothing is shared until you confirm it in the app.',
    next: 'If you already have Tidex, tap Open in Tidex. If you just installed it, come back here and do the same.',
    open: 'Open in Tidex',
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
            <div className="flex flex-col items-center gap-3">
              <AppStoreButton label={getMarketingDictionary(locale).marketing.hero.appStoreCta} />
              <OpenInAppLink label={copy[locale].open} />
            </div>
            <p className="text-pretty text-sm leading-6 text-text-muted">{copy[locale].next}</p>
          </section>
          );
        })}
      </div>
    </main>
  );
}
