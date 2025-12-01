"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { Plus, Trash2, Users, X } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/app/Dialog";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { createShare, removeShare } from "@/app/[locale]/(app)/sharing/_actions/sharing";
import { useTranslations } from "@/lib/i18n/client";
import type { ShareRecipient } from "@/data-access/sharing";

type ManageSharingModalProps = {
  isOpen: boolean;
  onClose: () => void;
  recipients: ShareRecipient[];
  shareCapacity: { canAdd: boolean; currentCount: number; limit: number };
};

function getInitials(name: string | null | undefined): string {
  if (!name) return "?";
  return name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);
}

function getDisplayName(recipient: ShareRecipient): string {
  if (recipient.firstName) return recipient.firstName;
  if (recipient.email) return recipient.email.split("@")[0];
  if (recipient.phone) return recipient.phone;
  return "Bruker";
}

export function ManageSharingModal({
  isOpen,
  onClose,
  recipients,
  shareCapacity,
}: ManageSharingModalProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isAdding, startAddTransition] = useTransition();
  const [removingId, setRemovingId] = useState<string | null>(null);
  const [isRemoving, startRemoveTransition] = useTransition();

  // Get translation strings with fallbacks
  const sharing = t.pages?.sharing ?? {
    manageSharing: "Administrer deling",
    manageDescription: "Del vaktene dine med andre brukere. De kan se vaktene dine, men ikke redigere dem.",
    addRecipient: "Legg til mottaker",
    emailOrPhone: "E-post eller telefonnummer",
    add: "Legg til",
    recipientsCount: "mottakere",
    noRecipients: "Du har ikke delt med noen enda",
    limitReached: "Du har nådd maksimalt antall mottakere",
    close: "Lukk",
  };

  const handleAdd = () => {
    if (!identifier.trim()) return;

    setError(null);
    startAddTransition(async () => {
      const result = await createShare(identifier.trim());
      if (result.success) {
        setIdentifier("");
        router.refresh();
      } else {
        setError(result.error);
      }
    });
  };

  const handleRemove = (recipientId: string) => {
    setRemovingId(recipientId);
    startRemoveTransition(async () => {
      const result = await removeShare(recipientId);
      if (!result.success) {
        setError(result.error);
      }
      setRemovingId(null);
      router.refresh();
    });
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-md sm:rounded-3xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Users className="h-5 w-5 text-text-muted" />
            {sharing.manageSharing}
          </DialogTitle>
          <DialogDescription>{sharing.manageDescription}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4 pt-2">
          {/* Add recipient form */}
          {shareCapacity.canAdd ? (
            <div className="space-y-2">
              <label className="text-sm font-medium text-text-secondary">
                {sharing.addRecipient}
              </label>
              <div className="flex gap-2">
                <Input
                  type="text"
                  placeholder={sharing.emailOrPhone}
                  value={identifier}
                  onChange={(e) => {
                    setIdentifier(e.target.value);
                    setError(null);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      handleAdd();
                    }
                  }}
                  disabled={isAdding}
                  className="flex-1"
                />
                <Button
                  type="button"
                  onClick={handleAdd}
                  disabled={!identifier.trim() || isAdding}
                  loading={isAdding}
                  className="gap-2"
                >
                  <Plus className="h-4 w-4" />
                  {sharing.add}
                </Button>
              </div>
              {error && <p className="text-sm text-error">{error}</p>}
            </div>
          ) : (
            <div className="rounded-xl border border-border-subtle bg-surface-secondary px-4 py-3">
              <p className="text-sm text-text-secondary">
                {sharing.limitReached} ({shareCapacity.currentCount}/{shareCapacity.limit})
              </p>
            </div>
          )}

          {/* Recipients list */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-text-secondary">
                {sharing.recipientsCount}
              </span>
              <span className="text-sm text-text-muted">
                {shareCapacity.currentCount}/{shareCapacity.limit}
              </span>
            </div>

            {recipients.length === 0 ? (
              <div className="rounded-xl border border-border-subtle bg-surface-secondary px-4 py-6 text-center">
                <p className="text-sm text-text-muted">{sharing.noRecipients}</p>
              </div>
            ) : (
              <div className="space-y-2">
                {recipients.map((recipient) => (
                  <div
                    key={recipient.id}
                    className="flex items-center gap-3 rounded-xl border border-border-subtle bg-surface-primary px-4 py-3"
                  >
                    <span className="relative inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-surface-secondary text-sm font-semibold text-text-primary">
                      {recipient.profilePictureUrl ? (
                        <Image
                          src={recipient.profilePictureUrl}
                          alt={getDisplayName(recipient)}
                          fill
                          sizes="40px"
                          className="object-cover"
                          unoptimized
                        />
                      ) : (
                        getInitials(recipient.firstName ?? recipient.email)
                      )}
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-text-primary truncate">
                        {getDisplayName(recipient)}
                      </p>
                      {recipient.email && (
                        <p className="text-xs text-text-muted truncate">{recipient.email}</p>
                      )}
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={() => handleRemove(recipient.id)}
                      disabled={isRemoving && removingId === recipient.id}
                      loading={isRemoving && removingId === recipient.id}
                      className="text-error hover:bg-error-subtle"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="mt-4 flex justify-end">
          <Button type="button" variant="ghost" onClick={onClose}>
            {sharing.close}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
