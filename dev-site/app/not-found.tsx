import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-4">
      <h1 className="mb-4 text-6xl font-bold text-text-primary">404</h1>
      <p className="mb-8 text-xl text-text-secondary">Page not found</p>
      <Link
        href="/"
        className="rounded-full bg-linear-to-r from-brand-gradient-start to-brand-gradient-end px-6 py-3 font-semibold text-text-inverse shadow-app transition-transform hover:scale-105"
      >
        Go Home
      </Link>
    </div>
  );
}
