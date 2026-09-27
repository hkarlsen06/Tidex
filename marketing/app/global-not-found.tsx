import type { Metadata } from 'next';
import { RootShell, rootMetadata, rootViewport } from '@/components/RootShell';

export const metadata: Metadata = {
  ...rootMetadata,
  title: 'Page not found | Tidex',
  robots: { index: false },
};
export const viewport = rootViewport;

export default function GlobalNotFound() {
  const linkClassName =
    'rounded-full border border-white/12 bg-white/8 px-5 py-2.5 font-semibold text-text-primary transition-colors hover:bg-white/12';

  return (
    <RootShell lang="en">
      <main className="flex min-h-screen flex-col items-center justify-center gap-6 px-6 text-center text-text-primary">
        <h1 className="text-3xl font-semibold sm:text-4xl">Page not found</h1>
        <p className="max-w-md text-base leading-7 text-text-secondary">
          This page does not exist.{' '}
          <span lang="no">Denne siden finnes ikke.</span>
        </p>
        <div className="flex flex-wrap justify-center gap-3 text-sm">
          <a href="/en/" className={linkClassName}>
            Go to the front page
          </a>
          <a href="/no/" lang="no" className={linkClassName}>
            Gå til forsiden
          </a>
        </div>
      </main>
    </RootShell>
  );
}
