import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-5 text-center">
      <span className="eyebrow">404</span>
      <h1 className="mt-4 text-[clamp(2rem,6vw,3.5rem)] font-semibold tracking-[-0.04em]">
        This page does not exist
      </h1>
      <p className="mt-4 max-w-md text-base leading-7 text-text-secondary">
        The link may be out of date, or the page has moved.
      </p>
      <Link
        href="/"
        className="mt-9 inline-flex h-12 items-center gap-2.5 rounded-full bg-white px-5.5 text-sm font-semibold text-text-inverse shadow-[0_2px_24px_rgba(255,255,255,0.12)] transition-all duration-200 hover:shadow-[0_4px_32px_rgba(255,255,255,0.2)] active:scale-[0.98]"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to home
      </Link>
    </div>
  );
}
