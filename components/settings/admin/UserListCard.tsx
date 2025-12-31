"use client";

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
} from "lucide-react";
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
  admin: "Admin",
  pro: "Pro",
  max: "Max",
  trial: "Prøve",
  free: "Gratis",
};

const PLAN_VARIANTS: Record<
  string,
  "default" | "secondary" | "outline" | "destructive"
> = {
  admin: "destructive",
  max: "default",
  pro: "secondary",
  trial: "outline",
  free: "outline",
};

type ActionType =
  | "ban"
  | "unban"
  | "grant_grandfathered"
  | "revoke_grandfathered"
  | "create_trial"
  | "revoke_trial";

interface Props {
  refreshTrigger?: number;
}

export function UserListCard({ refreshTrigger }: Props) {
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
  const [confirmDialog, setConfirmDialog] = useState<{
    open: boolean;
    type: ActionType;
    user: UserListItem | null;
  }>({ open: false, type: "ban", user: null });

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

  const formatDate = (dateString: string | null) => {
    if (!dateString) return "-";
    const date = new Date(dateString);
    return date.toLocaleDateString("nb-NO", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  };

  const getActionTitle = (type: ActionType): string => {
    switch (type) {
      case "ban":
        return "Utesteng bruker?";
      case "unban":
        return "Fjern utestengelse?";
      case "grant_grandfathered":
        return "Gi livstidstilgang?";
      case "revoke_grandfathered":
        return "Fjern livstidstilgang?";
      case "create_trial":
        return "Opprett prøveperiode?";
      case "revoke_trial":
        return "Avslutt prøveperiode?";
    }
  };

  const getActionDescription = (type: ActionType, user: UserListItem): string => {
    const contact = user.email ?? user.phone ?? user.id.slice(0, 8);
    switch (type) {
      case "ban":
        return `Brukeren ${contact} vil bli utestengt fra tjenesten.`;
      case "unban":
        return `Brukeren ${contact} vil få tilgang til tjenesten igjen.`;
      case "grant_grandfathered":
        return `Brukeren ${contact} vil få livstidstilgang til Pro-funksjoner.`;
      case "revoke_grandfathered":
        return `Brukeren ${contact} vil miste livstidstilgang til Pro-funksjoner.`;
      case "create_trial":
        return `Brukeren ${contact} vil få 30 dagers prøveperiode med Pro-tilgang.`;
      case "revoke_trial":
        return `Prøveperioden til ${contact} vil avsluttes umiddelbart.`;
    }
  };

  const isDestructiveAction = (type: ActionType): boolean => {
    return ["ban", "revoke_grandfathered", "revoke_trial"].includes(type);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Brukere</h3>
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
          placeholder="Søk etter e-post, tlf eller navn..."
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
          Søkeresultatene kan være ufullstendige. Prøv et mer spesifikt søk.
        </p>
      )}

      {loading ? (
        <div className="text-center py-8 text-text-muted">Laster...</div>
      ) : users.length === 0 ? (
        <div className="text-center py-8 text-text-muted">
          Ingen brukere funnet
        </div>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 px-2 font-medium">Navn</th>
                  <th className="text-left py-2 px-2 font-medium">ID</th>
                  <th className="text-left py-2 px-2 font-medium">E-post/tlf</th>
                  <th className="text-left py-2 px-2 font-medium">
                    Sist aktiv
                  </th>
                  <th className="text-left py-2 px-2 font-medium">Abo.</th>
                  <th className="text-left py-2 px-2 font-medium">Før PW</th>
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
                          title="Kopier ID"
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
                              title={user.email ? "Kopier e-post" : "Kopier tlf"}
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
                    <td className="py-2 px-2 text-text-secondary">
                      {formatDate(user.lastActive)}
                    </td>
                    <td className="py-2 px-2">
                      <Badge variant={PLAN_VARIANTS[user.plan]}>
                        {PLAN_LABELS[user.plan]}
                      </Badge>
                    </td>
                    <td className="py-2 px-2">
                      <div className="flex gap-1 flex-wrap">
                        {user.isGrandfathered && (
                          <Badge variant="default">Livstid</Badge>
                        )}
                        {user.isBanned && (
                          <Badge variant="destructive">Utestengt</Badge>
                        )}
                        {!user.isGrandfathered && !user.isBanned && (
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
                          {/* Ban/Unban - not available for admins or self */}
                          {!user.isAdmin && (
                            <>
                              {user.isBanned ? (
                                <DropdownMenuItem
                                  onClick={() =>
                                    setConfirmDialog({
                                      open: true,
                                      type: "unban",
                                      user,
                                    })
                                  }
                                >
                                  <UserCheck className="h-4 w-4 mr-2" />
                                  Fjern utestengelse
                                </DropdownMenuItem>
                              ) : (
                                <DropdownMenuItem
                                  onClick={() =>
                                    setConfirmDialog({
                                      open: true,
                                      type: "ban",
                                      user,
                                    })
                                  }
                                  className="text-destructive focus:text-destructive"
                                >
                                  <Ban className="h-4 w-4 mr-2" />
                                  Utesteng bruker
                                </DropdownMenuItem>
                              )}
                              <DropdownMenuSeparator />
                            </>
                          )}

                          {/* Grandfathered toggle */}
                          {user.isGrandfathered ? (
                            <DropdownMenuItem
                              onClick={() =>
                                setConfirmDialog({
                                  open: true,
                                  type: "revoke_grandfathered",
                                  user,
                                })
                              }
                              className="text-destructive focus:text-destructive"
                            >
                              <X className="h-4 w-4 mr-2" />
                              Fjern livstidstilgang
                            </DropdownMenuItem>
                          ) : (
                            <DropdownMenuItem
                              onClick={() =>
                                setConfirmDialog({
                                  open: true,
                                  type: "grant_grandfathered",
                                  user,
                                })
                              }
                            >
                              <Gift className="h-4 w-4 mr-2" />
                              Gi livstidstilgang
                            </DropdownMenuItem>
                          )}

                          {/* Trial actions */}
                          {user.plan === "trial" ? (
                            <DropdownMenuItem
                              onClick={() =>
                                setConfirmDialog({
                                  open: true,
                                  type: "revoke_trial",
                                  user,
                                })
                              }
                              className="text-destructive focus:text-destructive"
                            >
                              <X className="h-4 w-4 mr-2" />
                              Avslutt prøveperiode
                            </DropdownMenuItem>
                          ) : user.plan === "free" ? (
                            <DropdownMenuItem
                              onClick={() =>
                                setConfirmDialog({
                                  open: true,
                                  type: "create_trial",
                                  user,
                                })
                              }
                            >
                              <Play className="h-4 w-4 mr-2" />
                              Gi prøveperiode
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

          {/* Infinite scroll trigger */}
          <div ref={loadMoreRef} className="py-4 text-center">
            {loadingMore && (
              <div className="flex items-center justify-center gap-2 text-text-muted">
                <Loader2 className="h-4 w-4 animate-spin" />
                <span>Laster flere...</span>
              </div>
            )}
            {!hasMore && users.length > 0 && (
              <p className="text-sm text-text-muted">
                Alle brukere er lastet ({users.length} totalt)
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
            <AlertDialogCancel>Avbryt</AlertDialogCancel>
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
              Bekreft
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
