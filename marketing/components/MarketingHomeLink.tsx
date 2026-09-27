import Image from 'next/image';
import type { Locale } from '@/lib/i18n/config';
import tidexWordmark from '@/public/brand/tidex-wordmark-dark.svg';

export function MarketingHomeLink({ locale }: { locale: Locale }) {
  return (
    <a href={`/${locale}/`} className="inline-flex shrink-0 items-center">
      <Image src={tidexWordmark} alt="Tidex" className="h-7 w-auto" />
    </a>
  );
}
