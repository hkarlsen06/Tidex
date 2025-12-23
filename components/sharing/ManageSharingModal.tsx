"use client";

import { useState, useTransition, useOptimistic } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { Plus, Trash2, Users, DollarSign, Eye, EyeOff, Loader2, Share2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/app/Dialog";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { Switch } from "@/components/app/Switch";
import { Checkbox } from "@/components/app/Checkbox";
import {
  createShare,
  removeShare,
  toggleShareEarnings,
  blockSharer,
  unblockSharer,
  shareBack,
} from "@/app/[locale]/(app)/sharing/_actions/sharing";
import { useTranslations } from "@/lib/i18n/client";
import type { Friend } from "@/data-access/sharing";

type ManageSharingModalProps = {
  isOpen: boolean;
  onClose: () => void;
  friends: Friend[];
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

function formatPhoneNumber(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  const localNumber = digits.startsWith("47") && digits.length === 10
    ? digits.slice(2)
    : digits;

  if (localNumber.length === 8) {
    return `${localNumber.slice(0, 3)} ${localNumber.slice(3, 5)} ${localNumber.slice(5)}`;
  }
  return localNumber;
}

function getSecondaryInfo(friend: Friend): string | null {
  if (friend.phone) return formatPhoneNumber(friend.phone);
  if (friend.email) return friend.email;
  return null;
}

function FriendAvatar({ friend, displayName }: { friend: Friend; displayName: string }) {
  const avatarUrl = friend.profilePictureUrl || friend.oauthAvatarUrl || null;

  if (avatarUrl) {
    return (
      <span className="relative inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-surface-secondary text-sm font-semibold text-text-primary">
        <Image
          src={avatarUrl}
          alt={displayName}
          fill
          sizes="40px"
          className="object-cover"
          unoptimized
        />
      </span>
    );
  }

  return (
    <span className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface-secondary text-sm font-semibold text-text-primary">
      {getInitials(friend.firstName ?? friend.email)}
    </span>
  );
}

type OptimisticAction =
  | { type: "toggleVisibility"; id: string; blocked: boolean }
  | { type: "toggleEarnings"; id: string; showEarnings: boolean }
  | { type: "remove"; id: string }
  | { type: "shareBack"; id: string };

export function ManageSharingModal({
  isOpen,
  onClose,
  friends,
  shareCapacity,
}: ManageSharingModalProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [isAddFormExpanded, setIsAddFormExpanded] = useState(false);
  const [identifier, setIdentifier] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isAdding, startAddTransition] = useTransition();
  const [actionId, setActionId] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const [newRecipientShowEarnings, setNewRecipientShowEarnings] = useState(false);

  // Optimistic state for friends
  const [optimisticFriends, setOptimisticFriends] = useOptimistic(
    friends,
    (state, action: OptimisticAction) => {
      if (action.type === "toggleVisibility") {
        return state.map((f) =>
          f.id === action.id && f.sharesWithMe
            ? { ...f, sharesWithMe: { ...f.sharesWithMe, blocked: action.blocked } }
            : f
        );
      }
      if (action.type === "toggleEarnings") {
        return state.map((f) =>
          f.id === action.id && f.iShareWith
            ? { ...f, iShareWith: { ...f.iShareWith, showEarningsToThem: action.showEarnings } }
            : f
        );
      }
      if (action.type === "remove") {
        // Remove the iShareWith portion (they can still share with us)
        return state.map((f) =>
          f.id === action.id
            ? { ...f, iShareWith: null }
            : f
        ).filter((f) => f.sharesWithMe || f.iShareWith); // Remove if neither direction exists
      }
      if (action.type === "shareBack") {
        return state.map((f) =>
          f.id === action.id
            ? {
                ...f,
                iShareWith: {
                  showEarningsToThem: false,
                  sharedAt: new Date().toISOString(),
                },
              }
            : f
        );
      }
      return state;
    }
  );

  // Get translation strings with fallbacks
  const sharing = t.pages?.sharing ?? {
    manageSharing: "Administrer deling",
    manageDescription: "Del vaktene dine med andre brukere. De kan se vaktene dine, men ikke redigere dem.",
    addRecipient: "Legg til venn",
    emailOrPhone: "E-post eller telefonnummer",
    add: "Legg til",
    friends: "Venner",
    noFriends: "Ingen venner enda",
    limitReached: "Du har nådd maksimalt antall delinger",
    close: "Lukk",
    showEarnings: "Vis inntjening",
    showEarningsDescription: "La personen se hva du tjener",
    showInList: "Vis i listen",
    hideFromList: "Skjul fra listen",
    shareBack: "Del tilbake",
    stopSharing: "Slutt å dele",
    user: "Bruker",
    mutualShares: "Gjensidig deling",
    mutualSharesDesc: "Ser hverandres vakter",
    iShareWith: "Deler med",
    iShareWithDesc: "Kan se dine vakter",
    sharesWithMe: "Deler med deg",
    sharesWithMeDesc: "Du kan se deres vakter",
  };

  // Helper to get display name with localized fallback
  const getLocalizedDisplayName = (friend: Friend): string => {
    if (friend.firstName) return friend.firstName;
    if (friend.email) return friend.email.split("@")[0];
    if (friend.phone) return friend.phone;
    return sharing.user ?? "Bruker";
  };

  const handleAdd = () => {
    if (!identifier.trim()) return;

    setError(null);
    startAddTransition(async () => {
      const result = await createShare(identifier.trim(), { showEarnings: newRecipientShowEarnings });
      if (result.success) {
        setIdentifier("");
        setNewRecipientShowEarnings(false);
        setIsAddFormExpanded(false);
        router.refresh();
      } else {
        setError(result.error);
      }
    });
  };

  const handleToggleVisibility = (friendId: string, currentlyBlocked: boolean) => {
    setActionId(friendId);

    startTransition(async () => {
      const newBlocked = !currentlyBlocked;
      setOptimisticFriends({ type: "toggleVisibility", id: friendId, blocked: newBlocked });

      const result = newBlocked
        ? await blockSharer(friendId)
        : await unblockSharer(friendId);

      if (!result.success) {
        setError(result.error);
        router.refresh();
      }
      setActionId(null);
    });
  };

  const handleToggleEarnings = (friendId: string, currentValue: boolean) => {
    setActionId(friendId);

    startTransition(async () => {
      const newValue = !currentValue;
      setOptimisticFriends({ type: "toggleEarnings", id: friendId, showEarnings: newValue });

      const result = await toggleShareEarnings(friendId, newValue);
      if (!result.success) {
        setError(result.error);
        router.refresh();
      }
      setActionId(null);
    });
  };

  const handleRemove = (friendId: string) => {
    setActionId(friendId);

    startTransition(async () => {
      setOptimisticFriends({ type: "remove", id: friendId });

      const result = await removeShare(friendId);
      if (!result.success) {
        setError(result.error);
        router.refresh();
      }
      setActionId(null);
    });
  };

  const handleShareBack = (friendId: string) => {
    setActionId(friendId);

    startTransition(async () => {
      setOptimisticFriends({ type: "shareBack", id: friendId });

      const result = await shareBack(friendId);
      if (!result.success) {
        setError(result.error);
        router.refresh();
      }
      setActionId(null);
    });
  };

  // Helper to sort friends alphabetically using Norwegian locale
  const sortAlphabetically = (friends: Friend[]) => {
    return [...friends].sort((a, b) => {
      const aName = (a.firstName || a.email || a.phone || "").toLowerCase();
      const bName = (b.firstName || b.email || b.phone || "").toLowerCase();
      return aName.localeCompare(bName, "nb");
    });
  };

  // Split friends into three categories
  const mutualFriends = sortAlphabetically(
    optimisticFriends.filter((f) => f.sharesWithMe && f.iShareWith)
  );
  const onlyIShareWith = sortAlphabetically(
    optimisticFriends.filter((f) => !f.sharesWithMe && f.iShareWith)
  );
  const onlySharesWithMe = sortAlphabetically(
    optimisticFriends.filter((f) => f.sharesWithMe && !f.iShareWith)
  );

  const hasAnyFriends = optimisticFriends.length > 0;

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent
        className="max-w-[calc(100vw-2rem)] sm:max-w-md sm:rounded-3xl overflow-x-hidden"
        onOpenAutoFocus={(e) => e.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Users className="h-5 w-5 text-text-muted" />
            {sharing.manageSharing}
          </DialogTitle>
          <DialogDescription>{sharing.manageDescription}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4 pt-2 min-w-0">
          {/* Friends list */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-text-secondary">
                {sharing.friends}
              </span>
              <span className="text-sm text-text-muted">
                {shareCapacity.currentCount}/{shareCapacity.limit}
              </span>
            </div>

            {!hasAnyFriends ? (
              <div className="rounded-xl border border-border-subtle bg-surface-secondary px-4 py-6 text-center">
                <p className="text-sm text-text-muted">{sharing.noFriends}</p>
              </div>
            ) : (
              <div className="space-y-4">
                {/* Mutual shares section */}
                {mutualFriends.length > 0 && (
                  <div className="space-y-2">
                    <p className="text-xs text-text-muted">{sharing.mutualSharesDesc}</p>
                    <div className="divide-y divide-border-subtle rounded-xl border border-border-subtle bg-surface-primary">
                      {mutualFriends.map((friend) => {
                        const sharesWithMe = friend.sharesWithMe;
                        const iShareWith = friend.iShareWith;
                        const isBlocked = sharesWithMe?.blocked ?? false;
                        const isActionPending = isPending && actionId === friend.id;
                        const friendDisplayName = getLocalizedDisplayName(friend);

                        return (
                          <div
                            key={friend.id}
                            className="flex items-center gap-2 px-2 py-2.5 sm:gap-3 sm:px-3 sm:py-3"
                          >
                            <div className="shrink-0">
                              <FriendAvatar friend={friend} displayName={friendDisplayName} />
                            </div>
                            <div className="min-w-0 flex-1">
                              <p className="text-sm font-medium text-text-primary truncate-fade">
                                {friendDisplayName}
                              </p>
                              {getSecondaryInfo(friend) && (
                                <p className="truncate-fade text-xs text-text-muted">
                                  {getSecondaryInfo(friend)}
                                </p>
                              )}
                            </div>
                            <div className="flex items-center gap-1 shrink-0">
                              {sharesWithMe && (
                                <button
                                  type="button"
                                  onClick={() => handleToggleVisibility(friend.id, isBlocked)}
                                  disabled={isActionPending}
                                  className="p-1.5 rounded-md text-text-muted hover:text-text-primary hover:bg-surface-secondary transition-colors disabled:opacity-50"
                                  title={isBlocked ? sharing.showInList : sharing.hideFromList}
                                >
                                  {isBlocked ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                                </button>
                              )}
                              {iShareWith && (
                                <>
                                  <DollarSign className={`h-3.5 w-3.5 transition-colors ${iShareWith.showEarningsToThem ? "text-success" : "text-text-muted"}`} />
                                  <Switch
                                    checked={iShareWith.showEarningsToThem}
                                    onCheckedChange={() => handleToggleEarnings(friend.id, iShareWith.showEarningsToThem)}
                                    disabled={isActionPending}
                                    aria-label={sharing.showEarningsDescription}
                                  />
                                </>
                              )}
                              {iShareWith && (
                                <button
                                  type="button"
                                  onClick={() => handleRemove(friend.id)}
                                  disabled={isActionPending}
                                  className="ml-1 p-1.5 rounded-md text-text-muted hover:text-error hover:bg-error-subtle transition-colors disabled:opacity-50"
                                  title={sharing.stopSharing}
                                >
                                  <Trash2 className="h-4 w-4" />
                                </button>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* Only I share with them section */}
                {onlyIShareWith.length > 0 && (
                  <div className="space-y-2">
                    <p className="text-xs text-text-muted">{sharing.iShareWithDesc}</p>
                    <div className="divide-y divide-border-subtle rounded-xl border border-border-subtle bg-surface-primary">
                      {onlyIShareWith.map((friend) => {
                        const iShareWith = friend.iShareWith;
                        const isActionPending = isPending && actionId === friend.id;
                        const friendDisplayName = getLocalizedDisplayName(friend);

                        return (
                          <div
                            key={friend.id}
                            className="flex items-center gap-2 px-2 py-2.5 sm:gap-3 sm:px-3 sm:py-3"
                          >
                            <div className="shrink-0">
                              <FriendAvatar friend={friend} displayName={friendDisplayName} />
                            </div>
                            <div className="min-w-0 flex-1">
                              <p className="text-sm font-medium text-text-primary truncate-fade">
                                {friendDisplayName}
                              </p>
                              {getSecondaryInfo(friend) && (
                                <p className="truncate-fade text-xs text-text-muted">
                                  {getSecondaryInfo(friend)}
                                </p>
                              )}
                            </div>
                            <div className="flex items-center gap-1 shrink-0">
                              {iShareWith && (
                                <>
                                  <DollarSign className={`h-3.5 w-3.5 transition-colors ${iShareWith.showEarningsToThem ? "text-success" : "text-text-muted"}`} />
                                  <Switch
                                    checked={iShareWith.showEarningsToThem}
                                    onCheckedChange={() => handleToggleEarnings(friend.id, iShareWith.showEarningsToThem)}
                                    disabled={isActionPending}
                                    aria-label={sharing.showEarningsDescription}
                                  />
                                </>
                              )}
                              {iShareWith && (
                                <button
                                  type="button"
                                  onClick={() => handleRemove(friend.id)}
                                  disabled={isActionPending}
                                  className="ml-1 p-1.5 rounded-md text-text-muted hover:text-error hover:bg-error-subtle transition-colors disabled:opacity-50"
                                  title={sharing.stopSharing}
                                >
                                  <Trash2 className="h-4 w-4" />
                                </button>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* Only shares with me section */}
                {onlySharesWithMe.length > 0 && (
                  <div className="space-y-2">
                    <p className="text-xs text-text-muted">{sharing.sharesWithMeDesc}</p>
                    <div className="divide-y divide-border-subtle rounded-xl border border-border-subtle bg-surface-primary">
                      {onlySharesWithMe.map((friend) => {
                        const sharesWithMe = friend.sharesWithMe;
                        const isBlocked = sharesWithMe?.blocked ?? false;
                        const isActionPending = isPending && actionId === friend.id;
                        const friendDisplayName = getLocalizedDisplayName(friend);

                        return (
                          <div
                            key={friend.id}
                            className="flex items-center gap-2 px-2 py-2.5 sm:gap-3 sm:px-3 sm:py-3"
                          >
                            <div className="shrink-0">
                              <FriendAvatar friend={friend} displayName={friendDisplayName} />
                            </div>
                            <div className="min-w-0 flex-1">
                              <p className="text-sm font-medium text-text-primary truncate-fade">
                                {friendDisplayName}
                              </p>
                              {getSecondaryInfo(friend) && (
                                <p className="truncate-fade text-xs text-text-muted">
                                  {getSecondaryInfo(friend)}
                                </p>
                              )}
                            </div>
                            <div className="flex items-center gap-1 shrink-0">
                              {sharesWithMe && (
                                <button
                                  type="button"
                                  onClick={() => handleToggleVisibility(friend.id, isBlocked)}
                                  disabled={isActionPending}
                                  className="p-1.5 rounded-md text-text-muted hover:text-text-primary hover:bg-surface-secondary transition-colors disabled:opacity-50"
                                  title={isBlocked ? sharing.showInList : sharing.hideFromList}
                                >
                                  {isBlocked ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                                </button>
                              )}
                              <button
                                type="button"
                                onClick={() => handleShareBack(friend.id)}
                                disabled={isActionPending || !shareCapacity.canAdd}
                                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-brand-gradient-start text-white hover:opacity-90 transition-opacity disabled:opacity-50"
                                title={sharing.shareBack}
                              >
                                {isActionPending ? (
                                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                                ) : (
                                  <Share2 className="h-3.5 w-3.5" />
                                )}
                                <span>{sharing.shareBack}</span>
                              </button>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>

          <hr className="border-border-subtle" />

          {/* Add friend form */}
          {shareCapacity.canAdd ? (
            <div className="space-y-3">
              {!isAddFormExpanded ? (
                <Button
                  type="button"
                  onClick={() => setIsAddFormExpanded(true)}
                  className="w-full gap-2"
                >
                  <Plus className="h-4 w-4" />
                  {sharing.addRecipient}
                </Button>
              ) : (
                <div className="space-y-3">
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
                    autoFocus
                  />
                  <label htmlFor="new-recipient-show-earnings" className="flex items-center justify-between cursor-pointer select-none">
                    <span className="flex items-center gap-2">
                      <DollarSign className={`h-4 w-4 transition-colors ${newRecipientShowEarnings ? "text-success" : "text-text-muted"}`} />
                      <span className="text-sm text-text-secondary">{sharing.showEarnings}</span>
                    </span>
                    <Checkbox
                      id="new-recipient-show-earnings"
                      checked={newRecipientShowEarnings}
                      onCheckedChange={(checked) => setNewRecipientShowEarnings(checked === true)}
                      disabled={isAdding}
                      aria-label={sharing.showEarningsDescription}
                      className="h-5 w-5"
                    />
                  </label>
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => {
                        setIsAddFormExpanded(false);
                        setIdentifier("");
                        setNewRecipientShowEarnings(false);
                        setError(null);
                      }}
                      disabled={isAdding}
                      className="flex-1"
                    >
                      {sharing.close}
                    </Button>
                    <Button
                      type="button"
                      onClick={handleAdd}
                      disabled={!identifier.trim() || isAdding}
                      loading={isAdding}
                      className="flex-1 gap-2"
                    >
                      <Plus className="h-4 w-4" />
                      {sharing.add}
                    </Button>
                  </div>
                  {error && <p className="text-sm text-error">{error}</p>}
                </div>
              )}
            </div>
          ) : (
            <div className="rounded-xl border border-border-subtle bg-surface-secondary px-4 py-3">
              <p className="text-sm text-text-secondary">
                {sharing.limitReached} ({shareCapacity.currentCount}/{shareCapacity.limit})
              </p>
            </div>
          )}
        </div>

        <div className="mt-4 flex justify-end">
          <Button type="button" variant="outline" onClick={onClose}>
            {sharing.close}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
