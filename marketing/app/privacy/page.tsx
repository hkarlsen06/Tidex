import type { Metadata } from 'next';
import { PrivacyPolicy } from '@components/legal/PrivacyPolicy';

export const metadata: Metadata = {
  title: 'Personvernerklæring — kkarlsen.dev',
  description:
    'Les om hvordan kkarlsen.dev samler inn, bruker og beskytter dine personopplysninger.',
  openGraph: {
    title: 'Personvernerklæring — kkarlsen.dev',
    description:
      'Les om hvordan kkarlsen.dev samler inn, bruker og beskytter dine personopplysninger.',
    url: 'https://kkarlsen.dev/privacy',
    type: 'website',
  },
};

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-12 max-w-4xl">
        <PrivacyPolicy />
      </div>
    </div>
  );
}
