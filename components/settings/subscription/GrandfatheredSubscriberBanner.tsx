'use client';

import { Card } from '@appui/Card';
import { Heart } from 'lucide-react';

export function GrandfatheredSubscriberBanner() {
  return (
    <Card className="p-6 border-2 border-yellow-500/50 bg-gradient-to-br from-yellow-500/5 to-orange-500/5">
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <div className="p-3 rounded-full bg-red-500/10 dark:bg-red-500/20 flex-shrink-0">
            <Heart className="h-6 w-6 text-red-600 dark:text-red-500 fill-current" />
          </div>
          <div className="flex-1">
            <h3 className="text-lg font-bold">Takk for den utrolige støtten!</h3>
          </div>
        </div>
        <p className="text-sm text-text-secondary">
          Du var med fra starten og har fortsatt gratis tilgang til alle Pro-funksjoner for livet.
          I tillegg støtter du nå med et abonnement - det betyr alt for oss! ✰
        </p>
      </div>
    </Card>
  );
}
