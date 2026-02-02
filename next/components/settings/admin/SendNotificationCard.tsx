"use client";

import type { FormEvent } from "react";
import { useState, useEffect, useCallback } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { Input } from "@/components/app/Input";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/app/Select";
import { Checkbox } from "@/components/app/Checkbox";
import { sendBroadcastNotification } from "@/app/[locale]/(app)/settings/admin/_actions/sendBroadcastNotification";
import { previewTargetCount } from "@/app/[locale]/(app)/settings/admin/_actions/previewTargetCount";
import {
  getUsersWithPushTokens,
  type UserWithPushToken,
} from "@/app/[locale]/(app)/settings/admin/_actions/getUsersWithPushTokens";
import { cn } from "@/lib/cn";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";

type TargetAudience = "all" | "pro" | "active" | "specific";

interface Props {
  dictionary: Dictionary;
  onSuccess?: () => void;
}

export function SendNotificationCard({ onSuccess }: Props) {
  // English fields
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [deeplink, setDeeplink] = useState("tidex://");
  // Norwegian fields
  const [titleNo, setTitleNo] = useState("");
  const [bodyNo, setBodyNo] = useState("");
  const [deeplinkNo, setDeeplinkNo] = useState("");
  const [target, setTarget] = useState<TargetAudience>("all");
  const [specificUserId, setSpecificUserId] = useState("");
  const [includeSelf, setIncludeSelf] = useState(false);
  const [isPending, setIsPending] = useState(false);
  const [result, setResult] = useState<{
    success: boolean;
    message: string;
  } | null>(null);
  const [targetCount, setTargetCount] = useState<number | null>(null);
  const [users, setUsers] = useState<UserWithPushToken[]>([]);
  const [usersLoading, setUsersLoading] = useState(false);

  // Fetch users with push tokens when target is specific
  const fetchUsers = useCallback(async () => {
    setUsersLoading(true);
    const result = await getUsersWithPushTokens();
    if (result.success) {
      setUsers(result.users);
    }
    setUsersLoading(false);
  }, []);

  useEffect(() => {
    if (target === "specific" && users.length === 0) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      fetchUsers();
    }
  }, [target, users.length, fetchUsers]);

  // Preview target count when target or includeSelf changes
  useEffect(() => {
    if (target === "specific") {
      return;
    }
    let cancelled = false;
    const fetchCount = async () => {
      const res = await previewTargetCount(target, includeSelf);
      if (!cancelled) {
        setTargetCount(res.count);
      }
    };
    fetchCount();
    return () => { cancelled = true; };
  }, [target, includeSelf]);

  // Reset target count when switching to specific target
  const targetCountDisplay = target === "specific" ? null : targetCount;

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setIsPending(true);
    setResult(null);

    const res = await sendBroadcastNotification({
      title,
      titleNo,
      body,
      bodyNo,
      deeplink: deeplink || undefined,
      deeplinkNo: deeplinkNo || undefined,
      target,
      specificUserId: target === "specific" ? specificUserId : undefined,
      includeSelf,
    });

    setResult(res);
    if (res.success) {
      // Don't clear fields on success - user may want to send similar notification
      onSuccess?.();
    }
    setIsPending(false);
  };

  return (
    <Card className="p-6">
      <h3 className="text-lg font-semibold mb-4">Send Notification</h3>
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Title fields */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-text-muted">Title</span>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label htmlFor="notification-title-en" className="block text-xs text-text-muted mb-1">
                English <span>({title.length}/100)</span>
              </label>
              <Input
                id="notification-title-en"
                value={title}
                onChange={(e) => setTitle(e.target.value.slice(0, 100))}
                placeholder="Notification title"
                required
              />
            </div>
            <div>
              <label htmlFor="notification-title-no" className="block text-xs text-text-muted mb-1">
                Norwegian <span>({titleNo.length}/100)</span>
              </label>
              <Input
                id="notification-title-no"
                value={titleNo}
                onChange={(e) => setTitleNo(e.target.value.slice(0, 100))}
                placeholder="Varslingsoverskrift"
                required
              />
            </div>
          </div>
        </div>

        {/* Body fields */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-text-muted">Body</span>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label htmlFor="notification-body-en" className="block text-xs text-text-muted mb-1">
                English <span>({body.length}/500)</span>
              </label>
              <textarea
                id="notification-body-en"
                value={body}
                onChange={(e) => setBody(e.target.value.slice(0, 500))}
                placeholder="Notification message"
                required
                rows={3}
                className={cn(
                  "flex w-full min-w-0 max-w-full rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs transition-colors",
                  "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                  "focus:border-ring focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 md:text-sm",
                  "resize-none"
                )}
              />
            </div>
            <div>
              <label htmlFor="notification-body-no" className="block text-xs text-text-muted mb-1">
                Norwegian <span>({bodyNo.length}/500)</span>
              </label>
              <textarea
                id="notification-body-no"
                value={bodyNo}
                onChange={(e) => setBodyNo(e.target.value.slice(0, 500))}
                placeholder="Varslingsmelding"
                required
                rows={3}
                className={cn(
                  "flex w-full min-w-0 max-w-full rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs transition-colors",
                  "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                  "focus:border-ring focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 md:text-sm",
                  "resize-none"
                )}
              />
            </div>
          </div>
        </div>

        <div>
          <label htmlFor="notification-target" className="block text-sm font-medium mb-1">
            Target Audience
          </label>
          <Select
            value={target}
            onValueChange={(v) => setTarget(v as TargetAudience)}
          >
            <SelectTrigger id="notification-target">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All users</SelectItem>
              <SelectItem value="pro">Pro subscribers only</SelectItem>
              <SelectItem value="active">Active in last 7 days</SelectItem>
              <SelectItem value="specific">Specific user (testing)</SelectItem>
            </SelectContent>
          </Select>
          {targetCountDisplay !== null && (
            <p className="text-sm text-text-muted mt-1">
              Will send to {targetCountDisplay} user{targetCountDisplay === 1 ? "" : "s"}
            </p>
          )}
        </div>

        {target === "specific" ? (
          <div className="space-y-2">
            <label htmlFor="specific-user-select" className="block text-sm font-medium">
              Select User
            </label>
            <Select
              value={specificUserId || undefined}
              onValueChange={(v) => setSpecificUserId(v)}
            >
              <SelectTrigger id="specific-user-select">
                <SelectValue placeholder={usersLoading ? "Loading users..." : "Select user"} />
              </SelectTrigger>
              <SelectContent>
                {usersLoading ? (
                  <SelectItem value="__loading__" disabled>
                    Loading users...
                  </SelectItem>
                ) : users.length === 0 ? (
                  <SelectItem value="__empty__" disabled>
                    No users with push tokens
                  </SelectItem>
                ) : (
                  users.map((user) => (
                    <SelectItem key={user.id} value={user.id}>
                      {user.name || user.email || user.phone || user.id.slice(0, 8)}
                    </SelectItem>
                  ))
                )}
              </SelectContent>
            </Select>
            <div>
              <label htmlFor="specific-user-id" className="block text-sm font-medium mb-1">
                User ID
              </label>
              <Input
                id="specific-user-id"
                value={specificUserId}
                onChange={(e) => setSpecificUserId(e.target.value)}
                placeholder="UUID"
                required
              />
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-2">
            <Checkbox
              id="includeSelf"
              checked={includeSelf}
              onCheckedChange={(checked) => setIncludeSelf(checked === true)}
            />
            <label htmlFor="includeSelf" className="text-sm">
              Include myself (for testing)
            </label>
          </div>
        )}

        {/* Deeplink fields */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-text-muted">Deeplink (optional)</span>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label htmlFor="notification-deeplink-en" className="block text-xs text-text-muted mb-1">
                English
              </label>
              <Input
                id="notification-deeplink-en"
                value={deeplink}
                onChange={(e) => setDeeplink(e.target.value)}
                placeholder="tidex://shifts or https://..."
              />
            </div>
            <div>
              <label htmlFor="notification-deeplink-no" className="block text-xs text-text-muted mb-1">
                Norwegian (optional, falls back to English)
              </label>
              <Input
                id="notification-deeplink-no"
                value={deeplinkNo}
                onChange={(e) => setDeeplinkNo(e.target.value)}
                placeholder="tidex://shifts or https://..."
              />
            </div>
          </div>
          <p className="text-xs text-text-muted">
            Any URL format allowed (tidex://, https://, /path)
          </p>
        </div>

        <Button type="submit" disabled={isPending || !title || !titleNo || !body || !bodyNo}>
          {isPending ? "Sending..." : "Send Notification"}
        </Button>

        {result && (
          <p className={result.success ? "text-green-600" : "text-red-600"}>
            {result.message}
          </p>
        )}
      </form>
    </Card>
  );
}
