import type { Metadata } from 'next';
import { devLocales, type DevLocale } from '../../lib/i18n-config';
import { getDevDictionary } from '../../lib/dictionaries';
import { DevLandingPage } from '../../components/DevLandingPage';

interface HomePageProps {
  params: Promise<{ locale: string }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: HomePageProps): Promise<Metadata> {
  const { locale } = await params;
  const validLocale = locale as DevLocale;
  const dictionary = getDevDictionary(validLocale);

  return {
    title: dictionary.home.hero.name + ' — ' + dictionary.home.hero.title,
    description: dictionary.home.hero.tagline,
  };
}

export default async function HomePage({ params }: HomePageProps) {
  const { locale } = await params;
  const validLocale = locale as DevLocale;
  const dictionary = getDevDictionary(validLocale);

  return <DevLandingPage locale={validLocale} dictionary={dictionary} />;
}
