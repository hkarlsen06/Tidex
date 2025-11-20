'use client';

import { useState, useTransition, useEffect } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/app/Dialog';
import { Button } from '@/components/app/Button';
import { CustomSupplementsEditor } from './CustomSupplementsEditor';
import { CustomSupplementModeDialog } from './CustomSupplementModeDialog';
import type { CustomSupplementsEditorData, CustomSupplementMode, CustomSupplementsData } from '@/lib/custom-supplements/types';
import { useTranslations } from '@/lib/i18n/client';
import { updateCustomSupplements } from '@/app/[locale]/(app)/shifts/_actions/updateCustomSupplements';
import { useRouter } from 'next/navigation';

interface CustomSupplementsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shiftId: string;
  seriesId?: string;
  shiftDate: string;
  existingSupplements?: CustomSupplementsData | null;
  hasPredefinedSupplements: boolean;
  onSaveSuccess?: (updatedSupplements: CustomSupplementsData | null) => void;
}

// Convert CustomSupplementsData to CustomSupplementsEditorData
function toEditorData(data: CustomSupplementsData | null): CustomSupplementsEditorData {
  if (!data) {
    return { mode: 'merge', rules: [] };
  }
  return {
    mode: data.mode,
    rules: data.rules.map((rule, index) => ({
      id: String(index),
      from: rule.from,
      to: rule.to,
      rate: rule.rate,
      percent: rule.percent,
      mode: rule.rate !== undefined ? ('rate' as const) : rule.percent !== undefined ? ('percent' as const) : undefined,
    })),
  };
}

// Convert CustomSupplementsEditorData to CustomSupplementsData
function fromEditorData(data: CustomSupplementsEditorData): CustomSupplementsData {
  return {
    mode: data.mode,
    rules: data.rules.map(({ id, mode, ...rule }) => rule as any),
  };
}

export function CustomSupplementsModal({
  open,
  onOpenChange,
  shiftId,
  seriesId,
  shiftDate,
  existingSupplements,
  hasPredefinedSupplements,
  onSaveSuccess,
}: CustomSupplementsModalProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [modeDialogOpen, setModeDialogOpen] = useState(false);
  const [editorOpen, setEditorOpen] = useState(false);
  const [customSupplements, setCustomSupplements] = useState<CustomSupplementsEditorData>(
    toEditorData(existingSupplements ?? null)
  );
  const [saving, startTransition] = useTransition();
  const [saveError, setSaveError] = useState<string | null>(null);

  // Sync external open prop with internal flow
  useEffect(() => {
    if (open) {
      if (existingSupplements) {
        // Editing existing - go straight to editor
        setCustomSupplements(toEditorData(existingSupplements));
        setEditorOpen(true);
        setModeDialogOpen(false);
      } else if (hasPredefinedSupplements) {
        // New + has predefined - show mode dialog
        setModeDialogOpen(true);
        setEditorOpen(false);
      } else {
        // New + no predefined - go straight to editor with merge mode
        setCustomSupplements({ mode: 'merge', rules: [] });
        setEditorOpen(true);
        setModeDialogOpen(false);
      }
    } else {
      // Reset state when closing
      setModeDialogOpen(false);
      setEditorOpen(false);
      setSaveError(null);
    }
  }, [open, existingSupplements, hasPredefinedSupplements]);

  // When modal opens, determine flow
  const handleOpenChange = (isOpen: boolean) => {
    if (isOpen) {
      if (existingSupplements) {
        // Editing existing - go straight to editor
        setCustomSupplements(toEditorData(existingSupplements));
        setEditorOpen(true);
        setModeDialogOpen(false);
      } else if (hasPredefinedSupplements) {
        // New + has predefined - show mode dialog
        setModeDialogOpen(true);
        setEditorOpen(false);
      } else {
        // New + no predefined - go straight to editor with merge mode
        setCustomSupplements({ mode: 'merge', rules: [] });
        setEditorOpen(true);
        setModeDialogOpen(false);
      }
    } else {
      // Reset state when closing
      setModeDialogOpen(false);
      setEditorOpen(false);
      setSaveError(null);
    }
    onOpenChange(isOpen);
  };

  const handleModeSelect = (mode: CustomSupplementMode) => {
    setCustomSupplements({ mode, rules: [] });
    setModeDialogOpen(false);
    setEditorOpen(true);
  };

  const handleSave = () => {
    setSaveError(null);
    startTransition(async () => {
      try {
        // Only save if there are valid rules, and convert editor data to storage format
        const dataToSave = customSupplements.rules.length > 0 ? fromEditorData(customSupplements) : null;

        await updateCustomSupplements({
          shiftId,
          seriesId,
          shiftDate,
          customSupplements: dataToSave,
        });

        handleOpenChange(false);

        // Immediately notify parent with the updated data
        onSaveSuccess?.(dataToSave);
      } catch (error: any) {
        setSaveError(error?.message || t.pages.shifts.details.errorUpdate);
      }
    });
  };

  const handleCancel = () => {
    handleOpenChange(false);
  };

  return (
    <>
      {/* Mode Selection Dialog */}
      <CustomSupplementModeDialog
        open={modeDialogOpen}
        onOpenChange={(isOpen) => {
          if (!isOpen) {
            handleOpenChange(false);
          }
        }}
        onModeSelect={handleModeSelect}
      />

      {/* Editor Dialog */}
      <Dialog
        open={editorOpen}
        onOpenChange={(isOpen) => {
          if (!isOpen) {
            handleOpenChange(false);
          }
        }}
      >
        <DialogContent className="sm:max-w-2xl sm:rounded-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {existingSupplements
                ? t.components.customSupplementsModal.titleEdit
                : t.components.customSupplementsModal.titleAdd}
            </DialogTitle>
          </DialogHeader>

          <div className="py-4">
            <CustomSupplementsEditor
              value={customSupplements}
              onChange={setCustomSupplements}
            />
          </div>

          {saveError && (
            <div className="text-sm text-error">{saveError}</div>
          )}

          <DialogFooter>
            <Button variant="ghost" onClick={handleCancel} disabled={saving}>
              {t.components.customSupplementsModal.cancel}
            </Button>
            <Button
              onClick={handleSave}
              disabled={saving}
              loading={saving}
            >
              {t.components.customSupplementsModal.save}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
