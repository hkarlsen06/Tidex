import type { Metadata } from 'next';
import { TermsOfService } from '@components/legal/TermsOfService';

export const metadata: Metadata = {
  title: 'Vilkår for bruk — kkarlsen.dev',
  description:
    'Les vilkårene for bruk av kkarlsen.dev og hva som forventes av brukere av tjenesten.',
  openGraph: {
    title: 'Vilkår for bruk — kkarlsen.dev',
    description:
      'Les vilkårene for bruk av kkarlsen.dev og hva som forventes av brukere av tjenesten.',
    url: 'https://kkarlsen.dev/terms',
    type: 'website',
  },
};

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-12 max-w-4xl">
        <TermsOfService />
      </div>
    </div>
  );
}
