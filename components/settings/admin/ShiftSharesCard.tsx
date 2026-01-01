"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import { Badge } from "@/components/app/Badge";
import { Label } from "@/components/app/Label";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/app/Select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/app/Dialog";
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
import {
  getShiftShares,
  type ShiftShareItem,
} from "@/app/[locale]/(app)/settings/admin/_actions/getShiftShares";
import {
  searchUsersForSelect,
  type UserSelectOption,
} from "@/app/[locale]/(app)/settings/admin/_actions/searchUsersForSelect";
import { createShiftShare } from "@/app/[locale]/(app)/settings/admin/_actions/createShiftShare";
import { updateShiftShare } from "@/app/[locale]/(app)/settings/admin/_actions/updateShiftShare";
import { deleteShiftShare } from "@/app/[locale]/(app)/settings/admin/_actions/deleteShiftShare";
import { checkExistingShare } from "@/app/[locale]/(app)/settings/admin/_actions/checkExistingShare";
import {
  Copy,
  Check,
  MoreHorizontal,
  Search,
  RefreshCw,
  Plus,
  Trash2,
  Loader2,
  AlertTriangle,
} from "lucide-react";

type NotificationFrequency = "instant" | "summary" | "muted";

interface Props {
  refreshTrigger?: number;
}

const PER_PAGE = 20;

export function ShiftSharesCard({ refreshTrigger }: Props) {
  const [shares, setShares] = useState<ShiftShareItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [search, setSearch] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [updatingRow, setUpdatingRow] = useState<string | null>(null);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [deleteDialog, setDeleteDialog] = useState<{
    open: boolean;
    share: ShiftShareItem | null;
  }>({ open: false, share: null });

  // Create form state
  const [createOwner, setCreateOwner] = useState<UserSelectOption | null>(null);
  const [createViewer, setCreateViewer] = useState<UserSelectOption | null>(null);
  const [createShowEarnings, setCreateShowEarnings] = useState(true);
  const [createNotificationFrequency, setCreateNotificationFrequency] =
    useState<NotificationFrequency>("instant");
  const [createError, setCreateError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [duplicateWarning, setDuplicateWarning] = useState<string | null>(null);
  const [checkingDuplicate, setCheckingDuplicate] = useState(false);

  // User search state
  const [ownerSearchQuery, setOwnerSearchQuery] = useState("");
  const [ownerSearchResults, setOwnerSearchResults] = useState<UserSelectOption[]>([]);
  const [ownerSearchLoading, setOwnerSearchLoading] = useState(false);
  const [showOwnerResults, setShowOwnerResults] = useState(false);
  const [viewerSearchQuery, setViewerSearchQuery] = useState("");
  const [viewerSearchResults, setViewerSearchResults] = useState<UserSelectOption[]>([]);
  const [viewerSearchLoading, setViewerSearchLoading] = useState(false);
  const [showViewerResults, setShowViewerResults] = useState(false);

  const ownerSearchRef = useRef<HTMLDivElement>(null);
  const viewerSearchRef = useRef<HTMLDivElement>(null);
  const ownerDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const viewerDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const loadMoreRef = useRef<HTMLDivElement | null>(null);

  const fetchShares = useCallback(
    async (pageNum: number, append: boolean = false) => {
      if (append) {
        setLoadingMore(true);
      } else {
        setLoading(true);
      }
      setError(null);

      const result = await getShiftShares({
        search,
        page: pageNum,
        pageSize: PER_PAGE,
        sortBy: "owner_name",
        sortOrder: "asc",
      });

      if (result.success) {
        if (append) {
          setShares((prev) => [...prev, ...result.shares]);
        } else {
          setShares(result.shares);
        }
        setHasMore(result.shares.length === PER_PAGE);
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
    fetchShares(1, false);
  }, [fetchShares, refreshTrigger]);

  // Reset when search changes
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPage(1);
    setHasMore(true);
    setShares([]);
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
          fetchShares(nextPage, true);
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
  }, [hasMore, loading, loadingMore, page, fetchShares]);

  // Debounced owner search
  useEffect(() => {
    if (ownerDebounceRef.current) {
      clearTimeout(ownerDebounceRef.current);
    }

    if (ownerSearchQuery.length < 2) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setOwnerSearchResults([]);
      setOwnerSearchLoading(false);
      return;
    }

    setOwnerSearchLoading(true);
    ownerDebounceRef.current = setTimeout(async () => {
      const result = await searchUsersForSelect({
        query: ownerSearchQuery,
        excludeUserId: createViewer?.id,
        limit: 20,
      });
      if (result.success) {
        setOwnerSearchResults(result.users);
      }
      setOwnerSearchLoading(false);
    }, 300);

    return () => {
      if (ownerDebounceRef.current) {
        clearTimeout(ownerDebounceRef.current);
      }
    };
  }, [ownerSearchQuery, createViewer?.id]);

  // Debounced viewer search
  useEffect(() => {
    if (viewerDebounceRef.current) {
      clearTimeout(viewerDebounceRef.current);
    }

    if (viewerSearchQuery.length < 2) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setViewerSearchResults([]);
      setViewerSearchLoading(false);
      return;
    }

    setViewerSearchLoading(true);
    viewerDebounceRef.current = setTimeout(async () => {
      const result = await searchUsersForSelect({
        query: viewerSearchQuery,
        excludeUserId: createOwner?.id,
        limit: 20,
      });
      if (result.success) {
        setViewerSearchResults(result.users);
      }
      setViewerSearchLoading(false);
    }, 300);

    return () => {
      if (viewerDebounceRef.current) {
        clearTimeout(viewerDebounceRef.current);
      }
    };
  }, [viewerSearchQuery, createOwner?.id]);

  // Close dropdowns when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        ownerSearchRef.current &&
        !ownerSearchRef.current.contains(event.target as Node)
      ) {
        setShowOwnerResults(false);
      }
      if (
        viewerSearchRef.current &&
        !viewerSearchRef.current.contains(event.target as Node)
      ) {
        setShowViewerResults(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Check for existing share when both users are selected
  useEffect(() => {
    if (!createOwner || !createViewer) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDuplicateWarning(null);
      return;
    }

    if (createOwner.id === createViewer.id) {
      setDuplicateWarning(null);
      return;
    }

    const checkDuplicate = async () => {
      setCheckingDuplicate(true);
      const result = await checkExistingShare({
        ownerId: createOwner.id,
        viewerId: createViewer.id,
      });

      if (result.success && result.exists) {
        setDuplicateWarning(
          `A share already exists between ${createOwner.label.split(" (")[0]} and ${createViewer.label.split(" (")[0]}`
        );
      } else {
        setDuplicateWarning(null);
      }
      setCheckingDuplicate(false);
    };

    checkDuplicate();
  }, [createOwner, createViewer]);

  const handleSearch = () => {
    setSearch(searchInput.trim());
  };

  const handleRefresh = () => {
    setPage(1);
    setHasMore(true);
    fetchShares(1, false);
  };

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const getUserDisplayName = (
    name: string | null,
    email: string | null,
    phone: string | null,
    id: string
  ): string => {
    return name ?? email ?? phone ?? id.slice(0, 3);
  };

  const handleUpdateShare = async (
    share: ShiftShareItem,
    updates: {
      showEarnings?: boolean;
      blocked?: boolean;
      notificationFrequency?: NotificationFrequency;
    }
  ) => {
    setUpdatingRow(share.id);

    // Optimistic update
    setShares((prev) =>
      prev.map((s) =>
        s.id === share.id
          ? {
              ...s,
              ...(updates.showEarnings !== undefined && {
                showEarnings: updates.showEarnings,
              }),
              ...(updates.blocked !== undefined && { blocked: updates.blocked }),
              ...(updates.notificationFrequency !== undefined && {
                notificationFrequency: updates.notificationFrequency,
              }),
            }
          : s
      )
    );

    const result = await updateShiftShare({
      shareId: share.id,
      ...updates,
    });

    if (!result.success) {
      // Revert on error
      setShares((prev) =>
        prev.map((s) => (s.id === share.id ? share : s))
      );
      setError(result.message);
    }

    setUpdatingRow(null);
  };

  const handleDeleteShare = async (share: ShiftShareItem) => {
    setUpdatingRow(share.id);

    const result = await deleteShiftShare({ shareId: share.id });

    if (result.success) {
      // Remove from local state
      setShares((prev) => prev.filter((s) => s.id !== share.id));
    } else {
      setError(result.message);
    }

    setUpdatingRow(null);
    setDeleteDialog({ open: false, share: null });
  };

  const handleCreateShare = async () => {
    if (!createOwner || !createViewer) {
      setCreateError("Velg både eier og seer");
      return;
    }

    if (createOwner.id === createViewer.id) {
      setCreateError("Eier og seer kan ikke være samme bruker");
      return;
    }

    setCreating(true);
    setCreateError(null);

    const result = await createShiftShare({
      ownerId: createOwner.id,
      viewerId: createViewer.id,
      showEarnings: createShowEarnings,
      notificationFrequency: createNotificationFrequency,
    });

    if (result.success) {
      setCreateDialogOpen(false);
      resetCreateForm();
      // Refresh from beginning
      setPage(1);
      setHasMore(true);
      await fetchShares(1, false);
    } else {
      setCreateError(result.message);
    }

    setCreating(false);
  };

  const resetCreateForm = () => {
    setCreateOwner(null);
    setCreateViewer(null);
    setCreateShowEarnings(true);
    setCreateNotificationFrequency("instant");
    setCreateError(null);
    setDuplicateWarning(null);
    setOwnerSearchQuery("");
    setViewerSearchQuery("");
    setOwnerSearchResults([]);
    setViewerSearchResults([]);
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Shift Shares</h3>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="icon"
            onClick={handleRefresh}
            disabled={loading}
          >
            <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          </Button>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => setCreateDialogOpen(true)}
          >
            <Plus className="h-4 w-4 mr-1" />
            New Share
          </Button>
        </div>
      </div>

      <div className="flex gap-2 mb-4">
        <Input
          placeholder="Search by name, email, phone, or ID..."
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

      {loading ? (
        <div className="text-center py-8 text-text-muted">Loading...</div>
      ) : shares.length === 0 ? (
        <div className="text-center py-8 text-text-muted">
          No shift shares found
        </div>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 px-2 font-medium">Viewer</th>
                  <th className="text-left py-2 px-2 font-medium">Owner</th>
                  <th className="text-left py-2 px-2 font-medium">Created</th>
                  <th className="text-left py-2 px-2 font-medium">Earnings</th>
                  <th className="text-left py-2 px-2 font-medium">Blocked</th>
                  <th className="text-left py-2 px-2 font-medium">Notifications</th>
                  <th className="text-right py-2 px-2 font-medium">...</th>
                </tr>
              </thead>
              <tbody>
                {shares.map((share) => (
                  <tr
                    key={share.id}
                    className="border-b border-border-subtle hover:bg-surface-secondary/50"
                  >
                    <td className="py-2 px-2">
                      <div className="flex items-center gap-1">
                        <span className="truncate max-w-32">
                          {getUserDisplayName(
                            share.viewerName,
                            share.viewerEmail,
                            share.viewerPhone,
                            share.viewerId
                          )}
                        </span>
                        <code className="text-xs text-text-muted ml-1">
                          {share.viewerId.slice(0, 3)}..
                        </code>
                        <button
                          onClick={() =>
                            copyToClipboard(share.viewerId, `viewer-${share.id}`)
                          }
                          className="p-1 hover:bg-surface-secondary rounded shrink-0"
                          title="Copy viewer ID"
                        >
                          {copiedId === `viewer-${share.id}` ? (
                            <Check className="h-3 w-3 text-green-600" />
                          ) : (
                            <Copy className="h-3 w-3 text-text-muted" />
                          )}
                        </button>
                      </div>
                    </td>
                    <td className="py-2 px-2">
                      <div className="flex items-center gap-1">
                        <span className="truncate max-w-32">
                          {getUserDisplayName(
                            share.ownerName,
                            share.ownerEmail,
                            share.ownerPhone,
                            share.ownerId
                          )}
                        </span>
                        <code className="text-xs text-text-muted ml-1">
                          {share.ownerId.slice(0, 3)}..
                        </code>
                        <button
                          onClick={() =>
                            copyToClipboard(share.ownerId, `owner-${share.id}`)
                          }
                          className="p-1 hover:bg-surface-secondary rounded shrink-0"
                          title="Copy owner ID"
                        >
                          {copiedId === `owner-${share.id}` ? (
                            <Check className="h-3 w-3 text-green-600" />
                          ) : (
                            <Copy className="h-3 w-3 text-text-muted" />
                          )}
                        </button>
                      </div>
                    </td>
                    <td className="py-2 px-2 text-text-secondary whitespace-nowrap">
                      {formatDate(share.createdAt)}
                    </td>
                    <td className="py-2 px-2">
                      <button
                        onClick={() =>
                          handleUpdateShare(share, {
                            showEarnings: !share.showEarnings,
                          })
                        }
                        disabled={updatingRow === share.id}
                      >
                        <Badge
                          variant={share.showEarnings ? "default" : "outline"}
                          className={
                            updatingRow === share.id ? "opacity-50" : "cursor-pointer"
                          }
                        >
                          {share.showEarnings ? "Yes" : "No"}
                        </Badge>
                      </button>
                    </td>
                    <td className="py-2 px-2">
                      <button
                        onClick={() =>
                          handleUpdateShare(share, { blocked: !share.blocked })
                        }
                        disabled={updatingRow === share.id}
                      >
                        <Badge
                          variant={share.blocked ? "destructive" : "outline"}
                          className={
                            updatingRow === share.id ? "opacity-50" : "cursor-pointer"
                          }
                        >
                          {share.blocked ? "Yes" : "No"}
                        </Badge>
                      </button>
                    </td>
                    <td className="py-2 px-2">
                      <Select
                        value={share.notificationFrequency}
                        onValueChange={(value: NotificationFrequency) =>
                          handleUpdateShare(share, { notificationFrequency: value })
                        }
                        disabled={updatingRow === share.id}
                      >
                        <SelectTrigger className="w-28 h-8">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="instant">Instant</SelectItem>
                          <SelectItem value="summary">Summary</SelectItem>
                          <SelectItem value="muted">Muted</SelectItem>
                        </SelectContent>
                      </Select>
                    </td>
                    <td className="py-2 px-2 text-right">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button
                            variant="ghost"
                            size="icon"
                            disabled={updatingRow === share.id}
                          >
                            <MoreHorizontal className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem
                            onClick={() =>
                              setDeleteDialog({ open: true, share })
                            }
                            className="text-destructive focus:text-destructive"
                          >
                            <Trash2 className="h-4 w-4 mr-2" />
                            Delete share
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
            {!hasMore && shares.length > 0 && (
              <p className="text-sm text-text-muted">
                All shares loaded ({shares.length} total)
              </p>
            )}
          </div>
        </>
      )}

      {/* Create Dialog */}
      <Dialog
        open={createDialogOpen}
        onOpenChange={(open) => {
          if (!open) resetCreateForm();
          setCreateDialogOpen(open);
        }}
      >
        <DialogContent className="max-w-md w-[calc(100vw-2rem)]">
          <DialogHeader>
            <DialogTitle>Create Shift Share</DialogTitle>
            <DialogDescription>
              Create a new shift sharing relationship between two users.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4 overflow-hidden">
            {/* Owner Search */}
            <div className="space-y-2 min-w-0" ref={ownerSearchRef}>
              <Label>Owner (shares their shifts)</Label>
              {createOwner ? (
                <div className="flex items-center justify-between gap-2 p-2 border rounded-md bg-surface-secondary min-w-0">
                  <span className="text-sm truncate min-w-0 flex-1">{createOwner.label}</span>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setCreateOwner(null)}
                    className="shrink-0"
                  >
                    Change
                  </Button>
                </div>
              ) : (
                <div className="relative">
                  <Input
                    placeholder="Search by name, email, or ID..."
                    value={ownerSearchQuery}
                    onChange={(e) => setOwnerSearchQuery(e.target.value)}
                    onFocus={() => setShowOwnerResults(true)}
                    className="w-full"
                  />
                  {showOwnerResults && ownerSearchQuery.length >= 2 && (
                    <div className="absolute z-50 w-full mt-1 bg-background border rounded-md shadow-lg max-h-60 overflow-auto">
                      {ownerSearchLoading ? (
                        <div className="flex items-center justify-center p-4">
                          <Loader2 className="h-4 w-4 animate-spin" />
                        </div>
                      ) : ownerSearchResults.length === 0 ? (
                        <div className="p-4 text-sm text-text-muted text-center">
                          No users found
                        </div>
                      ) : (
                        ownerSearchResults.map((user) => (
                          <button
                            key={user.id}
                            onClick={() => {
                              setCreateOwner(user);
                              setOwnerSearchQuery("");
                              setShowOwnerResults(false);
                            }}
                            className="w-full text-left px-4 py-2 hover:bg-surface-secondary text-sm truncate"
                          >
                            {user.label}
                          </button>
                        ))
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Viewer Search */}
            <div className="space-y-2 min-w-0" ref={viewerSearchRef}>
              <Label>Viewer (can see shifts)</Label>
              {createViewer ? (
                <div className="flex items-center justify-between gap-2 p-2 border rounded-md bg-surface-secondary min-w-0">
                  <span className="text-sm truncate min-w-0 flex-1">{createViewer.label}</span>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setCreateViewer(null)}
                    className="shrink-0"
                  >
                    Change
                  </Button>
                </div>
              ) : (
                <div className="relative">
                  <Input
                    placeholder="Search by name, email, or ID..."
                    value={viewerSearchQuery}
                    onChange={(e) => setViewerSearchQuery(e.target.value)}
                    onFocus={() => setShowViewerResults(true)}
                    className="w-full"
                  />
                  {showViewerResults && viewerSearchQuery.length >= 2 && (
                    <div className="absolute z-50 w-full mt-1 bg-background border rounded-md shadow-lg max-h-60 overflow-auto">
                      {viewerSearchLoading ? (
                        <div className="flex items-center justify-center p-4">
                          <Loader2 className="h-4 w-4 animate-spin" />
                        </div>
                      ) : viewerSearchResults.length === 0 ? (
                        <div className="p-4 text-sm text-text-muted text-center">
                          No users found
                        </div>
                      ) : (
                        viewerSearchResults.map((user) => (
                          <button
                            key={user.id}
                            onClick={() => {
                              setCreateViewer(user);
                              setViewerSearchQuery("");
                              setShowViewerResults(false);
                            }}
                            className="w-full text-left px-4 py-2 hover:bg-surface-secondary text-sm truncate"
                          >
                            {user.label}
                          </button>
                        ))
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Duplicate warning */}
            {checkingDuplicate && (
              <div className="flex items-center gap-2 text-sm text-text-muted">
                <Loader2 className="h-4 w-4 animate-spin" />
                Checking for existing share...
              </div>
            )}
            {duplicateWarning && !checkingDuplicate && (
              <div className="flex items-start gap-2 p-3 bg-yellow-50 dark:bg-yellow-950/30 border border-yellow-200 dark:border-yellow-800 rounded-md">
                <AlertTriangle className="h-4 w-4 text-yellow-600 dark:text-yellow-500 shrink-0 mt-0.5" />
                <span className="text-sm text-yellow-700 dark:text-yellow-400">
                  {duplicateWarning}
                </span>
              </div>
            )}

            {/* Options */}
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-2">
                <Label htmlFor="showEarnings">Show earnings</Label>
                <input
                  id="showEarnings"
                  type="checkbox"
                  checked={createShowEarnings}
                  onChange={(e) => setCreateShowEarnings(e.target.checked)}
                  className="h-4 w-4"
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Notification frequency</Label>
              <Select
                value={createNotificationFrequency}
                onValueChange={(value: NotificationFrequency) =>
                  setCreateNotificationFrequency(value)
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="instant">Instant</SelectItem>
                  <SelectItem value="summary">Summary</SelectItem>
                  <SelectItem value="muted">Muted</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {createError && (
              <p className="text-sm text-red-600">{createError}</p>
            )}
          </div>

          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setCreateDialogOpen(false)}
              disabled={creating}
            >
              Cancel
            </Button>
            <Button onClick={handleCreateShare} disabled={creating}>
              {creating && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
              Create
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <AlertDialog
        open={deleteDialog.open}
        onOpenChange={(open: boolean) =>
          !open && setDeleteDialog({ open: false, share: null })
        }
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete shift share?</AlertDialogTitle>
            <AlertDialogDescription>
              {deleteDialog.share && (
                <>
                  This will remove the sharing relationship between{" "}
                  <strong>
                    {getUserDisplayName(
                      deleteDialog.share.ownerName,
                      deleteDialog.share.ownerEmail,
                      deleteDialog.share.ownerPhone,
                      deleteDialog.share.ownerId
                    )}
                  </strong>{" "}
                  and{" "}
                  <strong>
                    {getUserDisplayName(
                      deleteDialog.share.viewerName,
                      deleteDialog.share.viewerEmail,
                      deleteDialog.share.viewerPhone,
                      deleteDialog.share.viewerId
                    )}
                  </strong>
                  . The viewer will no longer be able to see the owner&apos;s shifts.
                </>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (deleteDialog.share) {
                  handleDeleteShare(deleteDialog.share);
                }
              }}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
