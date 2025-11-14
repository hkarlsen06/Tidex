import type { Metadata } from 'next';
import { devLocales, type DevLocale } from '../../../lib/i18n-config';
import { getDevDictionary } from '../../../lib/dictionaries';
import { ProjectsPage } from '../../../components/ProjectsPage';

interface ProjectsPageProps {
  params: Promise<{ locale: DevLocale }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: ProjectsPageProps): Promise<Metadata> {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return {
    title: dictionary.projects.title + ' — Hjalmar Karlsen',
    description: dictionary.projects.subtitle,
  };
}

export default async function Projects({ params }: ProjectsPageProps) {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return <ProjectsPage dictionary={dictionary} />;
}
