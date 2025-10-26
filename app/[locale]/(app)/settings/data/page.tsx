import { redirect } from 'next/navigation';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { DataForm } from '@components/settings/data/DataForm';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);
  return {
    title: t.pages.settings.data.title,
  };
}

export default async function DataPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect('/login');
  }

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <div className="mt-6">
        <DataForm t={t} />
      </div>
    </div>
  );
}
