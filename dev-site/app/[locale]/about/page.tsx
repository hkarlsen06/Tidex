import type { Metadata } from 'next';
import { devLocales, type DevLocale } from '../../../lib/i18n-config';
import { getDevDictionary } from '../../../lib/dictionaries';
import { AboutPage } from '../../../components/AboutPage';

interface AboutPageProps {
  params: Promise<{ locale: DevLocale }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: AboutPageProps): Promise<Metadata> {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return {
    title: dictionary.about.title + ' — Hjalmar Karlsen',
    description: dictionary.about.subtitle,
  };
}

export default async function About({ params }: AboutPageProps) {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return <AboutPage dictionary={dictionary} />;
}
