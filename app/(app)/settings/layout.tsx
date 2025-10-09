'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

const settingsNav = [
  { href: '/settings/profile', label: 'Profil' },
  { href: '/settings/pay', label: 'Lønn' },
  { href: '/settings/display', label: 'Utseende' },
  { href: '/settings/preferences', label: 'Preferanser' },
  { href: '/settings/data', label: 'Data' },
];

export default function SettingsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <h1 className="text-3xl font-bold mb-8">Innstillinger</h1>

      <div className="flex flex-col md:flex-row gap-8">
        {/* Desktop Sidebar Navigation */}
        <aside className="hidden md:block w-64 shrink-0">
          <nav className="sticky top-8 space-y-1">
            {settingsNav.map((item) => {
              const isActive = pathname === item.href;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    'block px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-surface-secondary text-text-primary'
                      : 'text-text-secondary hover:bg-surface-primary hover:text-text-primary'
                  )}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
        </aside>

        {/* Mobile Horizontal Tabs */}
        <div className="md:hidden -mx-4 px-4 overflow-x-auto">
          <nav className="flex gap-2 pb-4 min-w-max">
            {settingsNav.map((item) => {
              const isActive = pathname === item.href;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    'px-4 py-2 rounded-lg text-sm font-medium whitespace-nowrap transition-colors',
                    isActive
                      ? 'bg-surface-secondary text-text-primary'
                      : 'text-text-secondary hover:bg-surface-primary hover:text-text-primary'
                  )}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
        </div>

        {/* Main Content */}
        <main className="flex-1 min-w-0">
          {children}
        </main>
      </div>
    </div>
  );
}
