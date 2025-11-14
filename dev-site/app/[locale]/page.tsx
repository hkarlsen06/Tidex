import type { Metadata } from 'next';
import { devLocales, type DevLocale } from '../../lib/i18n-config';
import { getDevDictionary } from '../../lib/dictionaries';
import { DevLandingPage } from '../../components/DevLandingPage';

interface HomePageProps {
  params: Promise<{ locale: DevLocale }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: HomePageProps): Promise<Metadata> {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return {
    title: dictionary.home.hero.name + ' — ' + dictionary.home.hero.title,
    description: dictionary.home.hero.tagline,
  };
}

export default async function HomePage({ params }: HomePageProps) {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return <DevLandingPage locale={locale} dictionary={dictionary} />;
}
