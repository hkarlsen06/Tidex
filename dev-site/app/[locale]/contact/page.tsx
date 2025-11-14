import type { Metadata } from 'next';
import { devLocales, type DevLocale } from '../../../lib/i18n-config';
import { getDevDictionary } from '../../../lib/dictionaries';
import { ContactPage } from '../../../components/ContactPage';

interface ContactPageProps {
  params: Promise<{ locale: string }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: ContactPageProps): Promise<Metadata> {
  const { locale } = await params;
  const validLocale = locale as DevLocale;
  const dictionary = getDevDictionary(validLocale);

  return {
    title: dictionary.contact.title + ' — Hjalmar Karlsen',
    description: dictionary.contact.subtitle,
  };
}

export default async function Contact({ params }: ContactPageProps) {
  const { locale } = await params;
  const validLocale = locale as DevLocale;
  const dictionary = getDevDictionary(validLocale);

  return <ContactPage dictionary={dictionary} />;
}
