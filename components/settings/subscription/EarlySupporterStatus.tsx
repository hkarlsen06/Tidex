'use client';

import { Card } from '@appui/Card';
import { Badge } from '@appui/Badge';
import { Separator } from '@appui/Separator';
import { Heart } from 'lucide-react';

export function EarlySupporterStatus() {
  return (
    <Card className="p-6 border-2 border-text-primary bg-gradient-to-br from-surface-primary to-surface-secondary">
      <div className="space-y-6">
        <div className="flex items-start justify-between">
          <div className="flex items-start gap-3">
            <div className="p-3 rounded-full bg-red-500/10 dark:bg-red-500/20">
              <Heart className="h-6 w-6 text-red-600 dark:text-red-500 fill-current" />
            </div>
            <div>
              <h3 className="text-lg font-semibold">Tidlig supporter</h3>
              <p className="text-sm text-text-secondary mt-1">
                Takk for din tidlige støtte!
              </p>
            </div>
          </div>
          <Badge variant="default">Gratis Pro</Badge>
        </div>

        <Separator />

        <div className="p-4 bg-surface-secondary rounded-lg">
          <p className="text-sm text-text-secondary mb-4">
            Som en av våre tidlige brukere får du tilgang til alle Pro-funksjoner helt gratis som takk for din støtte.
          </p>

          <h4 className="font-semibold mb-2">Inkludert i planen din:</h4>
          <ul className="space-y-1 text-sm text-text-secondary">
            <li>✓ Lagre skift på tvers av måneder</li>
            <li>✓ Ubegrenset antall skift</li>
            <li>✓ Alle gratis funksjoner</li>
            <li>✓ Ingen reklame</li>
            <li>✓ Livstidstilgang til Pro-funksjoner</li>
          </ul>
        </div>

        <div className="flex items-center gap-2 p-3 bg-surface-primary rounded-lg border border-border-subtle">
          <div className="text-2xl">🎉</div>
          <div className="flex-1">
            <p className="text-sm font-medium">Du slipper å betale</p>
            <p className="text-xs text-text-secondary">Verdi: 29,90 kr/måned</p>
          </div>
        </div>
      </div>
    </Card>
  );
}
