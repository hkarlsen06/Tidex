import type { Metadata } from 'next';
import { devLocales, type DevLocale } from '../../../lib/i18n-config';
import { getDevDictionary } from '../../../lib/dictionaries';
import { ContactPage } from '../../../components/ContactPage';

interface ContactPageProps {
  params: Promise<{ locale: DevLocale }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: ContactPageProps): Promise<Metadata> {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return {
    title: dictionary.contact.title + ' — Hjalmar Karlsen',
    description: dictionary.contact.subtitle,
  };
}

export default async function Contact({ params }: ContactPageProps) {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return <ContactPage dictionary={dictionary} />;
}
