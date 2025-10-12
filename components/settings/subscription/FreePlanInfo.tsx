'use client';

import { Card } from '@appui/Card';
import { AlertCircle } from 'lucide-react';

export function FreePlanInfo() {
  return (
    <Card className="p-6 border-border-subtle bg-surface-secondary/50">
      <div className="flex gap-3">
        <AlertCircle className="h-5 w-5 text-text-secondary flex-shrink-0 mt-0.5" />
        <div>
          <h4 className="font-semibold text-sm mb-1">Du er på gratisplanen</h4>
          <p className="text-sm text-text-secondary">
            Med gratisplanen kan du bare ha skift i én måned av gangen.
            Oppgrader til Pro eller Max for å lagre skift på tvers av flere måneder.
          </p>
        </div>
      </div>
    </Card>
  );
}
