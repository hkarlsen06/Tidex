'use client';

import { Button } from '@/components/app/Button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/app/Dialog';
import type { CustomSupplementMode } from '@/lib/custom-supplements/types';
import { useTranslations } from '@/lib/i18n/client';

interface CustomSupplementModeDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onModeSelect: (mode: CustomSupplementMode) => void;
}

export function CustomSupplementModeDialog({
  open,
  onOpenChange,
  onModeSelect,
}: CustomSupplementModeDialogProps) {
  const { t } = useTranslations();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[calc(100%-2rem)] max-w-md p-4 gap-3">
        <DialogHeader className="space-y-1">
          <DialogTitle className="text-base font-semibold pr-8 leading-snug">
            {t.components.customSupplementModeDialog.title}
          </DialogTitle>
          <DialogDescription className="text-sm leading-normal">
            {t.components.customSupplementModeDialog.description}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-2">
          <button
            type="button"
            className="w-full rounded-lg border border-border bg-surface-primary hover:bg-surface-secondary p-3.5 text-left transition-colors"
            onClick={() => {
              onModeSelect('merge');
            }}
          >
            <div className="font-medium text-sm leading-snug mb-1">
              {t.components.customSupplementModeDialog.mergeTitle}
            </div>
            <div className="text-xs text-text-secondary leading-relaxed">
              {t.components.customSupplementModeDialog.mergeDescription}
            </div>
          </button>

          <button
            type="button"
            className="w-full rounded-lg border border-border bg-surface-primary hover:bg-surface-secondary p-3.5 text-left transition-colors"
            onClick={() => {
              onModeSelect('replace');
            }}
          >
            <div className="font-medium text-sm leading-snug mb-1">
              {t.components.customSupplementModeDialog.replaceTitle}
            </div>
            <div className="text-xs text-text-secondary leading-relaxed">
              {t.components.customSupplementModeDialog.replaceDescription}
            </div>
          </button>
        </div>

        <DialogFooter className="flex-row justify-end pt-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => onOpenChange(false)}
            className="text-sm"
          >
            {t.components.customSupplementModeDialog.cancel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
