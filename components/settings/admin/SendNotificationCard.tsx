"use client";

import type { FormEvent } from "react";
import { useState, useEffect } from "react";
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
import { cn } from "@/lib/cn";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";

type TargetAudience = "all" | "pro" | "active" | "specific";

interface Props {
  dictionary: Dictionary;
  onSuccess?: () => void;
}

export function SendNotificationCard({ onSuccess }: Props) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [deeplink, setDeeplink] = useState("");
  const [target, setTarget] = useState<TargetAudience>("all");
  const [specificUserId, setSpecificUserId] = useState("");
  const [includeSelf, setIncludeSelf] = useState(false);
  const [isPending, setIsPending] = useState(false);
  const [result, setResult] = useState<{
    success: boolean;
    message: string;
  } | null>(null);
  const [targetCount, setTargetCount] = useState<number | null>(null);

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
      body,
      deeplink: deeplink || undefined,
      target,
      specificUserId: target === "specific" ? specificUserId : undefined,
      includeSelf,
    });

    setResult(res);
    if (res.success) {
      setTitle("");
      setBody("");
      setDeeplink("");
      setSpecificUserId("");
      onSuccess?.();
    }
    setIsPending(false);
  };

  return (
    <Card className="p-6">
      <h3 className="text-lg font-semibold mb-4">Send Notification</h3>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="notification-title" className="block text-sm font-medium mb-1">
            Title <span className="text-text-muted">({title.length}/100)</span>
          </label>
          <Input
            id="notification-title"
            value={title}
            onChange={(e) => setTitle(e.target.value.slice(0, 100))}
            placeholder="Notification title"
            required
          />
        </div>

        <div>
          <label htmlFor="notification-body" className="block text-sm font-medium mb-1">
            Body <span className="text-text-muted">({body.length}/500)</span>
          </label>
          <textarea
            id="notification-body"
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
          <div>
            <label htmlFor="specific-user-id" className="block text-sm font-medium mb-1">User ID</label>
            <Input
              id="specific-user-id"
              value={specificUserId}
              onChange={(e) => setSpecificUserId(e.target.value)}
              placeholder="UUID"
              required
            />
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

        <div>
          <label htmlFor="notification-deeplink" className="block text-sm font-medium mb-1">
            Deeplink (optional)
          </label>
          <Input
            id="notification-deeplink"
            value={deeplink}
            onChange={(e) => setDeeplink(e.target.value)}
            placeholder="/shifts or /stats"
          />
          <p className="text-xs text-text-muted mt-1">
            Route to navigate when tapped. Must start with /
          </p>
        </div>

        <Button type="submit" disabled={isPending || !title || !body}>
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
