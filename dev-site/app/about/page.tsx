import { redirect } from 'next/navigation';
import { defaultDevLocale } from '../../lib/i18n-config';

export default function AboutRedirect() {
  redirect(`/${defaultDevLocale}/about`);
}
