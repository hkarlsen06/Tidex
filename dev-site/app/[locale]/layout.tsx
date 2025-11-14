import type { ReactNode } from 'react';
import { devLocales, type DevLocale } from '../../lib/i18n-config';
import { getDevDictionary } from '../../lib/dictionaries';
import { DevHeader } from '../../components/DevHeader';
import { LocaleLangSetter } from '../../components/LocaleLangSetter';
import ViewportHeightSetter from '../../components/ViewportHeightSetter';

interface LocaleLayoutProps {
  children: ReactNode;
  params: Promise<{ locale: DevLocale }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: LocaleLayoutProps) {
  const { locale } = await params;
  const dictionary = getDevDictionary(locale);

  return (
    <>
      <LocaleLangSetter locale={locale as any} />
      <ViewportHeightSetter />
      <DevHeader locale={locale} dictionary={dictionary} />
      <main>{children}</main>
    </>
  );
}
