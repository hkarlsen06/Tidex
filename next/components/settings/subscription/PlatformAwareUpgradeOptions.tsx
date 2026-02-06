'use client';

import { UpgradeOptions } from './UpgradeOptions';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface PlatformAwareUpgradeOptionsProps {
  t: Dictionary;
}

export function PlatformAwareUpgradeOptions({ t }: PlatformAwareUpgradeOptionsProps) {
  return <UpgradeOptions t={t} />;
}
