import type { ReactNode } from 'react';
import { RootShell, rootMetadata, rootViewport } from '@/components/RootShell';

export const metadata = rootMetadata;
export const viewport = rootViewport;

export default function InviteLayout({ children }: { children: ReactNode }) {
  return <RootShell lang="no">{children}</RootShell>;
}
