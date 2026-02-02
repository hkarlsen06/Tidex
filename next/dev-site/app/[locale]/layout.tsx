import type { ReactNode } from 'react';
import { devLocales, type DevLocale } from '../../lib/i18n-config';
import { getDevDictionary } from '../../lib/dictionaries';
import { DevHeader } from '../../components/DevHeader';
import { LocaleLangSetter } from '../../components/LocaleLangSetter';
import ViewportHeightSetter from '../../components/ViewportHeightSetter';

interface LocaleLayoutProps {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}

export async function generateStaticParams() {
  return devLocales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: LocaleLayoutProps) {
  const { locale } = await params;
  const validLocale = locale as DevLocale;
  const dictionary = getDevDictionary(validLocale);

  return (
    <>
      <LocaleLangSetter locale={validLocale as any} />
      <ViewportHeightSetter />
      <DevHeader locale={validLocale} dictionary={dictionary} />
      <main>{children}</main>
    </>
  );
}
