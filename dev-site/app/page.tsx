import { redirect } from 'next/navigation';
import { defaultDevLocale } from '../lib/i18n-config';

export default function RootPage() {
  redirect(`/${defaultDevLocale}`);
}
