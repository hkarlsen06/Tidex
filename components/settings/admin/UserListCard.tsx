"use client";

import type { ChangeEvent } from "react";
import { useState, useEffect, useCallback, useRef } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { Badge } from "@/components/app/Badge";
import {
  getUserList,
  type UserListItem,
} from "@/app/[locale]/(app)/settings/admin/_actions/getUserList";
import { toggleUserBan } from "@/app/[locale]/(app)/settings/admin/_actions/toggleUserBan";
import { toggleGrandfathered } from "@/app/[locale]/(app)/settings/admin/_actions/toggleGrandfathered";
import { toggleAdmin, checkIsSuperAdmin } from "@/app/[locale]/(app)/settings/admin/_actions/toggleAdmin";
import { createTrialSubscription } from "@/app/[locale]/(app)/settings/admin/_actions/createTrialSubscription";
import { revokeTrialSubscription } from "@/app/[locale]/(app)/settings/admin/_actions/revokeTrialSubscription";
import {
  Copy,
  Check,
  MoreHorizontal,
  Search,
  RefreshCw,
  Ban,
  UserCheck,
  Gift,
  X,
  Play,
  Loader2,
  UserCog,
  Shield,
  ShieldOff,
} from "lucide-react";
import { useRouter } from "next/navigation";
import { Label } from "@/components/app/Label";
import { Textarea } from "@/components/app/Textarea";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
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

type ActionType =
  | "ban"
  | "unban"
  | "grant_admin"
  | "revoke_admin"
  | "grant_grandfathered"
  | "revoke_grandfathered"
  | "create_trial"
  | "revoke_trial"
  | "impersonate";

interface Props {
  refreshTrigger?: number;
}

export function UserListCard({ refreshTrigger }: Props) {
  const router = useRouter();
  const [users, setUsers] = useState<UserListItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [search, setSearch] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [resultsArePartial, setResultsArePartial] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [actionPending, setActionPending] = useState<string | null>(null);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [confirmDialog, setConfirmDialog] = useState<{
    open: boolean;
    type: ActionType;
    user: UserListItem | null;
  }>({ open: false, type: "ban", user: null });
  const [impersonateDialog, setImpersonateDialog] = useState<{
    open: boolean;
    user: UserListItem | null;
    reason: string;
    loading: boolean;
    error: string | null;
  }>({ open: false, user: null, reason: "", loading: false, error: null });

  const observerRef = useRef<IntersectionObserver | null>(null);
  const loadMoreRef = useRef<HTMLDivElement | null>(null);

  const perPage = 20;

  const fetchUsers = useCallback(
    async (pageNum: number, append: boolean = false) => {
      if (append) {
        setLoadingMore(true);
      } else {
        setLoading(true);
      }
      setError(null);

      const result = await getUserList({ page: pageNum, perPage, search });

      if (result.success) {
        if (append) {
          setUsers((prev) => [...prev, ...result.users]);
        } else {
          setUsers(result.users);
        }
        setResultsArePartial(result.resultsArePartial);
        setHasMore(result.users.length === perPage);
      } else {
        setError(result.message);
      }

      if (append) {
        setLoadingMore(false);
      } else {
        setLoading(false);
      }
    },
    [search]
  );

  // Check if current user is superadmin
  useEffect(() => {
    checkIsSuperAdmin().then(setIsSuperAdmin);
  }, []);

  // Initial load and refresh trigger
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPage(1);
    setHasMore(true);
    fetchUsers(1, false);
  }, [fetchUsers, refreshTrigger]);

  // Reset when search changes
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPage(1);
    setHasMore(true);
    setUsers([]);
  }, [search]);

  // Set up Intersection Observer for endless scrolling
  useEffect(() => {
    if (observerRef.current) {
      observerRef.current.disconnect();
    }

    observerRef.current = new IntersectionObserver(
      (entries) => {
        const target = entries[0];
        if (target.isIntersecting && hasMore && !loading && !loadingMore) {
          const nextPage = page + 1;
          setPage(nextPage);
          fetchUsers(nextPage, true);
        }
      },
      { threshold: 0.1 }
    );

    if (loadMoreRef.current) {
      observerRef.current.observe(loadMoreRef.current);
    }

    return () => {
      if (observerRef.current) {
        observerRef.current.disconnect();
      }
    };
  }, [hasMore, loading, loadingMore, page, fetchUsers]);

  const handleSearch = () => {
    setSearch(searchInput.trim());
  };

  const handleRefresh = () => {
    setPage(1);
    setHasMore(true);
    fetchUsers(1, false);
  };

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const executeAction = async (type: ActionType, user: UserListItem) => {
    setActionPending(user.id);
    let result: { success: boolean; message: string };
    const targetEmail = user.email ?? user.phone ?? "unknown";

    switch (type) {
      case "ban":
        result = await toggleUserBan({
          targetUserId: user.id,
          targetEmail,
          ban: true,
        });
        break;
      case "unban":
        result = await toggleUserBan({
          targetUserId: user.id,
          targetEmail,
          ban: false,
        });
        break;
      case "grant_admin":
        result = await toggleAdmin({
          targetUserId: user.id,
          targetEmail,
          grant: true,
        });
        break;
      case "revoke_admin":
        result = await toggleAdmin({
          targetUserId: user.id,
          targetEmail,
          grant: false,
        });
        break;
      case "grant_grandfathered":
        result = await toggleGrandfathered({
          targetUserId: user.id,
          targetEmail,
          grant: true,
        });
        break;
      case "revoke_grandfathered":
        result = await toggleGrandfathered({
          targetUserId: user.id,
          targetEmail,
          grant: false,
        });
        break;
      case "create_trial":
        result = await createTrialSubscription({
          targetUserId: user.id,
          targetEmail,
        });
        break;
      case "revoke_trial":
        result = await revokeTrialSubscription({
          targetUserId: user.id,
          targetEmail,
        });
        break;
      default:
        result = { success: false, message: "Unknown action type" };
    }

    if (result.success) {
      // Refresh from the beginning to get updated data
      setPage(1);
      setHasMore(true);
      await fetchUsers(1, false);
    }
    setActionPending(null);
    setConfirmDialog({ open: false, type: "ban", user: null });
  };

  const handleImpersonate = async () => {
    if (!impersonateDialog.user || impersonateDialog.reason.trim().length < 5) {
      return;
    }

    setImpersonateDialog((prev) => ({ ...prev, loading: true, error: null }));

    try {
      const response = await fetch("/api/admin/impersonation/start", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          targetUserId: impersonateDialog.user.id,
          reason: impersonateDialog.reason.trim(),
        }),
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        setImpersonateDialog((prev) => ({
          ...prev,
          loading: false,
          error: data.error || "Failed to start impersonation",
        }));
        return;
      }

      // Success - close dialog and navigate to home
      setImpersonateDialog({
        open: false,
        user: null,
        reason: "",
        loading: false,
        error: null,
      });

      // Navigate to home as the impersonated user
      router.push("/");
      router.refresh();
    } catch {
      setImpersonateDialog((prev) => ({
        ...prev,
        loading: false,
        error: "Network error. Please try again.",
      }));
    }
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

  const getActionTitle = (type: ActionType): string => {
    switch (type) {
      case "ban":
        return "Ban user?";
      case "unban":
        return "Remove ban?";
      case "grant_admin":
        return "Grant admin access?";
      case "revoke_admin":
        return "Revoke admin access?";
      case "grant_grandfathered":
        return "Grant lifetime access?";
      case "revoke_grandfathered":
        return "Revoke lifetime access?";
      case "create_trial":
        return "Create trial?";
      case "revoke_trial":
        return "End trial?";
      case "impersonate":
        return "Impersonate user?";
    }
  };

  const getActionDescription = (type: ActionType, user: UserListItem): string => {
    const contact = user.email ?? user.phone ?? user.id.slice(0, 8);
    switch (type) {
      case "ban":
        return `User ${contact} will be banned from the service.`;
      case "unban":
        return `User ${contact} will regain access to the service.`;
      case "grant_admin":
        return `User ${contact} will be granted admin access and can manage users.`;
      case "revoke_admin":
        return `User ${contact} will lose admin access and management capabilities.`;
      case "grant_grandfathered":
        return `User ${contact} will be granted lifetime access to Pro features.`;
      case "revoke_grandfathered":
        return `User ${contact} will lose lifetime access to Pro features.`;
      case "create_trial":
        return `User ${contact} will receive a 30-day trial with Pro access.`;
      case "revoke_trial":
        return `The trial for ${contact} will end immediately.`;
      case "impersonate":
        return `You will be logged in as ${contact}. A banner will show you are impersonating.`;
    }
  };

  const isDestructiveAction = (type: ActionType): boolean => {
    return ["ban", "revoke_admin", "revoke_grandfathered", "revoke_trial"].includes(type);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Users</h3>
        <Button
          variant="ghost"
          size="icon"
          onClick={handleRefresh}
          disabled={loading}
        >
          <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
        </Button>
      </div>

      <div className="flex gap-2 mb-4">
        <Input
          placeholder="Search by email, phone, or name..."
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleSearch()}
          className="flex-1"
        />
        <Button variant="secondary" onClick={handleSearch}>
          <Search className="h-4 w-4" />
        </Button>
      </div>

      {error && <p className="text-red-600 mb-4">{error}</p>}
      {resultsArePartial && (
        <p className="text-yellow-600 text-sm mb-4">
          Search results may be incomplete. Try a more specific search.
        </p>
      )}

      {loading ? (
        <div className="text-center py-8 text-text-muted">Loading...</div>
      ) : users.length === 0 ? (
        <div className="text-center py-8 text-text-muted">
          No users found
        </div>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 px-2 font-medium">Name</th>
                  <th className="text-left py-2 px-2 font-medium">ID</th>
                  <th className="text-left py-2 px-2 font-medium">Email/Phone</th>
                  <th className="text-left py-2 px-2 font-medium whitespace-nowrap">
                    Last Sign In
                  </th>
                  <th className="text-left py-2 px-2 font-medium">Plan</th>
                  <th className="text-left py-2 px-2 font-medium">Status</th>
                  <th className="text-right py-2 px-2 font-medium">
                    ...
                  </th>
                </tr>
              </thead>
              <tbody>
                {users.map((user) => (
                  <tr
                    key={user.id}
                    className="border-b border-border-subtle hover:bg-surface-secondary/50"
                  >
                    <td className="py-2 px-2 text-text-secondary">
                      {user.name ?? "-"}
                    </td>
                    <td className="py-2 px-2">
                      <div className="flex items-center gap-1">
                        <code className="text-xs">{user.id.slice(0, 8)}</code>
                        <button
                          onClick={() => copyToClipboard(user.id, user.id)}
                          className="p-1 hover:bg-surface-secondary rounded"
                          title="Copy ID"
                        >
                          {copiedId === user.id ? (
                            <Check className="h-3 w-3 text-green-600" />
                          ) : (
                            <Copy className="h-3 w-3 text-text-muted" />
                          )}
                        </button>
                      </div>
                    </td>
                    <td className="py-2 px-2">
                      {(() => {
                        const contact = user.email ?? user.phone;
                        if (!contact) return <span className="text-text-muted">-</span>;
                        return (
                          <div className="flex items-center gap-1">
                            <span className="truncate max-w-50">{contact}</span>
                            <button
                              onClick={() =>
                                copyToClipboard(contact, `contact-${user.id}`)
                              }
                              className="p-1 hover:bg-surface-secondary rounded shrink-0"
                              title={user.email ? "Copy email" : "Copy phone"}
                            >
                              {copiedId === `contact-${user.id}` ? (
                                <Check className="h-3 w-3 text-green-600" />
                              ) : (
                                <Copy className="h-3 w-3 text-text-muted" />
                              )}
                            </button>
                          </div>
                        );
                      })()}
                    </td>
                    <td className="py-2 px-2 text-text-secondary whitespace-nowrap">
                      {formatDate(user.lastSignInAt)}
                    </td>
                    <td className="py-2 px-2">
                      <Badge variant={PLAN_VARIANTS[user.plan]}>
                        {PLAN_LABELS[user.plan]}
                      </Badge>
                    </td>
                    <td className="py-2 px-2">
                      <div className="flex gap-1 flex-wrap">
                        {user.isSuperAdmin && (
                          <Badge variant="destructive">Superadmin</Badge>
                        )}
                        {user.isAdmin && !user.isSuperAdmin && (
                          <Badge variant="destructive">Admin</Badge>
                        )}
                        {user.isGrandfathered && (
                          <Badge variant="default">Lifetime</Badge>
                        )}
                        {user.isBanned && (
                          <Badge variant="destructive">Banned</Badge>
                        )}
                        {!user.isSuperAdmin && !user.isAdmin && !user.isGrandfathered && !user.isBanned && (
                          <span className="text-text-muted">-</span>
                        )}
                      </div>
                    </td>
                    <td className="py-2 px-2 text-right">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button
                            variant="ghost"
                            size="icon"
                            disabled={actionPending === user.id}
                          >
                            <MoreHorizontal className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          {/* Impersonate - disabled for admin users */}
                          <DropdownMenuItem
                            onClick={() =>
                              !user.isAdmin &&
                              setImpersonateDialog({
                                open: true,
                                user,
                                reason: "",
                                loading: false,
                                error: null,
                              })
                            }
                            disabled={user.isAdmin}
                          >
                            <UserCog className="h-4 w-4 mr-2" />
                            Impersonate
                          </DropdownMenuItem>

                          <DropdownMenuSeparator />

                          {/* Admin section - Make admin first, then Revoke admin (destructive) */}
                          <DropdownMenuItem
                            onClick={() =>
                              isSuperAdmin &&
                              !user.isSuperAdmin &&
                              !user.isAdmin &&
                              setConfirmDialog({
                                open: true,
                                type: "grant_admin",
                                user,
                              })
                            }
                            disabled={!isSuperAdmin || user.isSuperAdmin || user.isAdmin}
                          >
                            <Shield className="h-4 w-4 mr-2" />
                            Make admin
                          </DropdownMenuItem>
                          <DropdownMenuItem
                            onClick={() =>
                              isSuperAdmin &&
                              !user.isSuperAdmin &&
                              user.isAdmin &&
                              setConfirmDialog({
                                open: true,
                                type: "revoke_admin",
                                user,
                              })
                            }
                            disabled={!isSuperAdmin || user.isSuperAdmin || !user.isAdmin}
                            className={isSuperAdmin && !user.isSuperAdmin && user.isAdmin ? "text-destructive focus:text-destructive" : ""}
                          >
                            <ShieldOff className="h-4 w-4 mr-2" />
                            Revoke admin
                          </DropdownMenuItem>

                          <DropdownMenuSeparator />

                          {/* Lifetime access section - Grant first, then Revoke (destructive) */}
                          <DropdownMenuItem
                            onClick={() =>
                              !user.isGrandfathered &&
                              setConfirmDialog({
                                open: true,
                                type: "grant_grandfathered",
                                user,
                              })
                            }
                            disabled={user.isGrandfathered}
                          >
                            <Gift className="h-4 w-4 mr-2" />
                            Grant lifetime access
                          </DropdownMenuItem>
                          <DropdownMenuItem
                            onClick={() =>
                              user.isGrandfathered &&
                              setConfirmDialog({
                                open: true,
                                type: "revoke_grandfathered",
                                user,
                              })
                            }
                            disabled={!user.isGrandfathered}
                            className={user.isGrandfathered ? "text-destructive focus:text-destructive" : ""}
                          >
                            <X className="h-4 w-4 mr-2" />
                            Revoke lifetime access
                          </DropdownMenuItem>

                          {/* Trial section - Grant first, then End (destructive) */}
                          <DropdownMenuItem
                            onClick={() =>
                              user.plan === "free" &&
                              setConfirmDialog({
                                open: true,
                                type: "create_trial",
                                user,
                              })
                            }
                            disabled={user.plan !== "free"}
                          >
                            <Play className="h-4 w-4 mr-2" />
                            Grant trial
                          </DropdownMenuItem>
                          <DropdownMenuItem
                            onClick={() =>
                              user.plan === "trial" &&
                              setConfirmDialog({
                                open: true,
                                type: "revoke_trial",
                                user,
                              })
                            }
                            disabled={user.plan !== "trial"}
                            className={user.plan === "trial" ? "text-destructive focus:text-destructive" : ""}
                          >
                            <X className="h-4 w-4 mr-2" />
                            End trial
                          </DropdownMenuItem>

                          <DropdownMenuSeparator />

                          {/* Ban section - Remove ban first, then Ban (destructive) */}
                          <DropdownMenuItem
                            onClick={() =>
                              !user.isAdmin &&
                              user.isBanned &&
                              setConfirmDialog({
                                open: true,
                                type: "unban",
                                user,
                              })
                            }
                            disabled={user.isAdmin || !user.isBanned}
                          >
                            <UserCheck className="h-4 w-4 mr-2" />
                            Remove ban
                          </DropdownMenuItem>
                          <DropdownMenuItem
                            onClick={() =>
                              !user.isAdmin &&
                              !user.isBanned &&
                              setConfirmDialog({
                                open: true,
                                type: "ban",
                                user,
                              })
                            }
                            disabled={user.isAdmin || user.isBanned}
                            className={!user.isAdmin && !user.isBanned ? "text-destructive focus:text-destructive" : ""}
                          >
                            <Ban className="h-4 w-4 mr-2" />
                            Ban user
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Infinite scroll trigger */}
          <div ref={loadMoreRef} className="py-4 text-center">
            {loadingMore && (
              <div className="flex items-center justify-center gap-2 text-text-muted">
                <Loader2 className="h-4 w-4 animate-spin" />
                <span>Loading more...</span>
              </div>
            )}
            {!hasMore && users.length > 0 && (
              <p className="text-sm text-text-muted">
                All users loaded ({users.length} total)
              </p>
            )}
          </div>
        </>
      )}

      <AlertDialog
        open={confirmDialog.open}
        onOpenChange={(open: boolean) =>
          !open && setConfirmDialog({ open: false, type: "ban", user: null })
        }
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {getActionTitle(confirmDialog.type)}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirmDialog.user &&
                getActionDescription(
                  confirmDialog.type,
                  confirmDialog.user
                )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (confirmDialog.user) {
                  executeAction(confirmDialog.type, confirmDialog.user);
                }
              }}
              className={
                isDestructiveAction(confirmDialog.type)
                  ? "bg-destructive text-destructive-foreground hover:bg-destructive/90"
                  : undefined
              }
            >
              Confirm
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Impersonate Dialog */}
      <AlertDialog
        open={impersonateDialog.open}
        onOpenChange={(open: boolean) => {
          if (!open && !impersonateDialog.loading) {
            setImpersonateDialog({
              open: false,
              user: null,
              reason: "",
              loading: false,
              error: null,
            });
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Impersonate User</AlertDialogTitle>
            <AlertDialogDescription>
              You will be logged in as{" "}
              <strong>
                {impersonateDialog.user?.name ??
                  impersonateDialog.user?.email ??
                  impersonateDialog.user?.phone ??
                  impersonateDialog.user?.id.slice(0, 8)}
              </strong>
              . A banner will indicate you are impersonating. Some actions will be
              restricted.
            </AlertDialogDescription>
          </AlertDialogHeader>

          <div className="py-4">
            <Label htmlFor="impersonate-reason">
              Reason for impersonation (required)
            </Label>
            <Textarea
              id="impersonate-reason"
              placeholder="e.g., Investigating user-reported bug #123"
              value={impersonateDialog.reason}
              onChange={(e: ChangeEvent<HTMLTextAreaElement>) =>
                setImpersonateDialog((prev) => ({
                  ...prev,
                  reason: e.target.value,
                  error: null,
                }))
              }
              disabled={impersonateDialog.loading}
              className="mt-2"
              rows={3}
            />
            {impersonateDialog.reason.length > 0 &&
              impersonateDialog.reason.trim().length < 5 && (
                <p className="text-sm text-destructive mt-1">
                  Please provide at least 5 characters
                </p>
              )}
            {impersonateDialog.error && (
              <p className="text-sm text-destructive mt-2">
                {impersonateDialog.error}
              </p>
            )}
          </div>

          <AlertDialogFooter>
            <AlertDialogCancel disabled={impersonateDialog.loading}>
              Cancel
            </AlertDialogCancel>
            <Button
              onClick={handleImpersonate}
              disabled={
                impersonateDialog.loading ||
                impersonateDialog.reason.trim().length < 5
              }
            >
              {impersonateDialog.loading ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Starting...
                </>
              ) : (
                "Start Impersonation"
              )}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
