"use client";

import { useState, useEffect } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { Badge } from "@/components/app/Badge";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/app/Select";
import {
  getSubscribers,
  type SubscriberData,
} from "@/app/[locale]/(app)/settings/admin/_actions/getSubscribers";
import { toggleGrandfathered } from "@/app/[locale]/(app)/settings/admin/_actions/toggleGrandfathered";
import { revokeTrialSubscription } from "@/app/[locale]/(app)/settings/admin/_actions/revokeTrialSubscription";
import { createTrialSubscription } from "@/app/[locale]/(app)/settings/admin/_actions/createTrialSubscription";
import { Copy, Check, MoreHorizontal, X, RefreshCw, Play } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/app/DropdownMenu";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/app/AlertDialog";

type FilterType = "all" | "pro" | "max" | "grandfathered" | "trial";

const PLAN_LABELS: Record<string, string> = {
  pro: "Pro",
  max: "Max",
  trial: "Trial",
  free: "Free",
};

const PLAN_VARIANTS: Record<
  string,
  "default" | "secondary" | "outline" | "destructive"
> = {
  max: "default",
  pro: "secondary",
  trial: "outline",
  free: "outline",
};

interface Props {
  refreshTrigger?: number;
}

export function SubscriberListCard({ refreshTrigger }: Props) {
  const [filter, setFilter] = useState<FilterType>("all");
  const [subscribers, setSubscribers] = useState<SubscriberData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [actionPending, setActionPending] = useState<string | null>(null);
  const [confirmDialog, setConfirmDialog] = useState<{
    open: boolean;
    type: "revoke_grandfathered" | "revoke_trial" | "create_trial";
    subscriber: SubscriberData | null;
  }>({ open: false, type: "revoke_grandfathered", subscriber: null });

  const fetchSubscribers = async () => {
    setLoading(true);
    setError(null);
    const result = await getSubscribers(filter);
    if (result.success) {
      setSubscribers(result.subscribers);
    } else {
      setError(result.message);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchSubscribers();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, refreshTrigger]);

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const handleRevokeGrandfathered = async (subscriber: SubscriberData) => {
    setActionPending(subscriber.userId);
    const targetEmail = subscriber.email ?? subscriber.phone ?? "unknown";
    const result = await toggleGrandfathered({
      targetUserId: subscriber.userId,
      targetEmail,
      grant: false,
    });
    if (result.success) {
      await fetchSubscribers();
    }
    setActionPending(null);
    setConfirmDialog({ open: false, type: "revoke_grandfathered", subscriber: null });
  };

  const handleRevokeTrial = async (subscriber: SubscriberData) => {
    setActionPending(subscriber.userId);
    const targetEmail = subscriber.email ?? subscriber.phone ?? "unknown";
    const result = await revokeTrialSubscription({
      targetUserId: subscriber.userId,
      targetEmail,
    });
    if (result.success) {
      await fetchSubscribers();
    }
    setActionPending(null);
    setConfirmDialog({ open: false, type: "revoke_trial", subscriber: null });
  };

  const handleCreateTrial = async (subscriber: SubscriberData) => {
    setActionPending(subscriber.userId);
    const targetEmail = subscriber.email ?? subscriber.phone ?? "unknown";
    const result = await createTrialSubscription({
      targetUserId: subscriber.userId,
      targetEmail,
    });
    if (result.success) {
      await fetchSubscribers();
    }
    setActionPending(null);
    setConfirmDialog({ open: false, type: "create_trial", subscriber: null });
  };

  const formatDate = (dateString: string | null) => {
    if (!dateString) return "-";
    const date = new Date(dateString);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  };

  const getContact = (subscriber: SubscriberData): string => {
    return subscriber.email ?? subscriber.phone ?? subscriber.userId.slice(0, 8);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Subscribers</h3>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="icon"
            onClick={fetchSubscribers}
            disabled={loading}
          >
            <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          </Button>
          <Select
            value={filter}
            onValueChange={(v) => setFilter(v as FilterType)}
          >
            <SelectTrigger className="w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All</SelectItem>
              <SelectItem value="pro">Pro</SelectItem>
              <SelectItem value="max">Max</SelectItem>
              <SelectItem value="grandfathered">Lifetime</SelectItem>
              <SelectItem value="trial">Trial</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>

      {error && <p className="text-red-600 mb-4">{error}</p>}

      {loading ? (
        <div className="text-center py-8 text-text-muted">Loading...</div>
      ) : subscribers.length === 0 ? (
        <div className="text-center py-8 text-text-muted">
          No subscribers found
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left py-2 px-2 font-medium">Name</th>
                <th className="text-left py-2 px-2 font-medium">ID</th>
                <th className="text-left py-2 px-2 font-medium">Email/Phone</th>
                <th className="text-left py-2 px-2 font-medium">Plan</th>
                <th className="text-left py-2 px-2 font-medium">Lifetime</th>
                <th className="text-left py-2 px-2 font-medium">Expires</th>
                <th className="text-right py-2 px-2 font-medium">...</th>
              </tr>
            </thead>
            <tbody>
              {subscribers.map((subscriber) => (
                <tr
                  key={subscriber.userId}
                  className="border-b border-border-subtle hover:bg-surface-secondary/50"
                >
                  <td className="py-2 px-2 text-text-secondary">
                    {subscriber.name ?? "-"}
                  </td>
                  <td className="py-2 px-2">
                    <div className="flex items-center gap-1">
                      <code className="text-xs">
                        {subscriber.userId.slice(0, 8)}
                      </code>
                      <button
                        onClick={() =>
                          copyToClipboard(subscriber.userId, subscriber.userId)
                        }
                        className="p-1 hover:bg-surface-secondary rounded"
                        title="Copy ID"
                      >
                        {copiedId === subscriber.userId ? (
                          <Check className="h-3 w-3 text-green-600" />
                        ) : (
                          <Copy className="h-3 w-3 text-text-muted" />
                        )}
                      </button>
                    </div>
                  </td>
                  <td className="py-2 px-2">
                    {(() => {
                      const contact = subscriber.email ?? subscriber.phone;
                      if (!contact) return <span className="text-text-muted">-</span>;
                      return (
                        <div className="flex items-center gap-1">
                          <span className="truncate max-w-50">{contact}</span>
                          <button
                            onClick={() =>
                              copyToClipboard(contact, `contact-${subscriber.userId}`)
                            }
                            className="p-1 hover:bg-surface-secondary rounded shrink-0"
                            title={subscriber.email ? "Copy email" : "Copy phone"}
                          >
                            {copiedId === `contact-${subscriber.userId}` ? (
                              <Check className="h-3 w-3 text-green-600" />
                            ) : (
                              <Copy className="h-3 w-3 text-text-muted" />
                            )}
                          </button>
                        </div>
                      );
                    })()}
                  </td>
                  <td className="py-2 px-2">
                    <Badge variant={PLAN_VARIANTS[subscriber.plan]}>
                      {PLAN_LABELS[subscriber.plan]}
                    </Badge>
                  </td>
                  <td className="py-2 px-2">
                    {subscriber.isGrandfathered ? (
                      <Badge variant="default">Yes</Badge>
                    ) : (
                      <span className="text-text-muted">-</span>
                    )}
                  </td>
                  <td className="py-2 px-2 text-text-secondary">
                    {formatDate(subscriber.currentPeriodEnd)}
                  </td>
                  <td className="py-2 px-2 text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon"
                          disabled={actionPending === subscriber.userId}
                        >
                          <MoreHorizontal className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        {subscriber.isGrandfathered && (
                          <DropdownMenuItem
                            onClick={() =>
                              setConfirmDialog({
                                open: true,
                                type: "revoke_grandfathered",
                                subscriber,
                              })
                            }
                            className="text-destructive focus:text-destructive"
                          >
                            <X className="h-4 w-4 mr-2" />
                            Revoke lifetime access
                          </DropdownMenuItem>
                        )}
                        {subscriber.plan === "trial" ? (
                          <DropdownMenuItem
                            onClick={() =>
                              setConfirmDialog({
                                open: true,
                                type: "revoke_trial",
                                subscriber,
                              })
                            }
                            className="text-destructive focus:text-destructive"
                          >
                            <X className="h-4 w-4 mr-2" />
                            End trial
                          </DropdownMenuItem>
                        ) : subscriber.plan === "free" ? (
                          <DropdownMenuItem
                            onClick={() =>
                              setConfirmDialog({
                                open: true,
                                type: "create_trial",
                                subscriber,
                              })
                            }
                          >
                            <Play className="h-4 w-4 mr-2" />
                            Grant trial
                          </DropdownMenuItem>
                        ) : null}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <AlertDialog
        open={confirmDialog.open}
        onOpenChange={(open: boolean) =>
          !open &&
          setConfirmDialog({ open: false, type: "revoke_grandfathered", subscriber: null })
        }
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmDialog.type === "revoke_grandfathered"
                ? "Revoke lifetime access?"
                : confirmDialog.type === "revoke_trial"
                  ? "End trial?"
                  : "Create trial?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirmDialog.type === "revoke_grandfathered"
                ? `Are you sure you want to revoke lifetime access for ${confirmDialog.subscriber ? getContact(confirmDialog.subscriber) : ""}? The user will lose access to Pro features.`
                : confirmDialog.type === "revoke_trial"
                  ? `Are you sure you want to end the trial for ${confirmDialog.subscriber ? getContact(confirmDialog.subscriber) : ""}? The user will lose access to Pro features immediately.`
                  : `User ${confirmDialog.subscriber ? getContact(confirmDialog.subscriber) : ""} will receive a 30-day trial with Pro access.`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (confirmDialog.subscriber) {
                  if (confirmDialog.type === "revoke_grandfathered") {
                    handleRevokeGrandfathered(confirmDialog.subscriber);
                  } else if (confirmDialog.type === "revoke_trial") {
                    handleRevokeTrial(confirmDialog.subscriber);
                  } else {
                    handleCreateTrial(confirmDialog.subscriber);
                  }
                }
              }}
              className={
                confirmDialog.type === "create_trial"
                  ? undefined
                  : "bg-destructive text-destructive-foreground hover:bg-destructive/90"
              }
            >
              Confirm
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
