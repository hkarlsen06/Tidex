"use client";

import { useEffect, useState } from "react";
import { Card } from "@/components/app/Card";
import {
  getBroadcastHistory,
  type BroadcastRecord,
} from "@/app/[locale]/(app)/settings/admin/_actions/getBroadcastHistory";
import { formatDistanceToNow } from "date-fns";
import { enUS } from "date-fns/locale";

const TARGET_LABELS: Record<string, string> = {
  all: "All users",
  pro: "Pro subscribers",
  active: "Active users",
  specific: "Specific user",
};

const STATUS_LABELS: Record<string, { label: string; className: string }> = {
  pending: { label: "Pending", className: "text-yellow-600" },
  queued: { label: "Queued", className: "text-blue-600" },
  partial_failure: { label: "Partial Failure", className: "text-orange-600" },
  complete: { label: "Complete", className: "text-green-600" },
};

export function NotificationHistoryCard({
  refreshTrigger,
}: {
  refreshTrigger: number;
}) {
  const [history, setHistory] = useState<BroadcastRecord[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const fetchHistory = async () => {
      const data = await getBroadcastHistory();
      if (!cancelled) {
        setHistory(data);
        setLoading(false);
      }
    };
    fetchHistory();
    return () => { cancelled = true; };
  }, [refreshTrigger]);

  return (
    <Card className="p-6">
      <h3 className="text-lg font-semibold mb-4">Recent Broadcasts</h3>
      {loading ? (
        <p className="text-text-muted">Loading...</p>
      ) : history.length === 0 ? (
        <p className="text-text-muted">No broadcasts sent yet</p>
      ) : (
        <div className="space-y-4">
          {history.map((record) => (
            <div
              key={record.id}
              className="border-b border-border pb-4 last:border-0 last:pb-0"
            >
              <div className="flex justify-between items-start gap-4">
                <div className="flex-1 min-w-0">
                  <p className="font-medium truncate">{record.title}</p>
                  <p className="text-sm text-text-muted">
                    {formatDistanceToNow(new Date(record.created_at), {
                      addSuffix: true,
                      locale: enUS,
                    })}
                    {" · "}
                    {TARGET_LABELS[record.target] || record.target}
                    {" · "}
                    {record.target_count} targeted
                    {" · "}
                    <span
                      className={
                        STATUS_LABELS[record.status]?.className || ""
                      }
                    >
                      {STATUS_LABELS[record.status]?.label || record.status}
                    </span>
                  </p>
                </div>
                <div className="text-right text-sm shrink-0">
                  <span className="text-green-600">
                    {record.sent_count} sent
                  </span>
                  {record.failed_count > 0 && (
                    <span className="text-red-600 ml-2">
                      {record.failed_count} failed
                    </span>
                  )}
                  {record.pending_count > 0 && (
                    <span className="text-yellow-600 ml-2">
                      {record.pending_count} pending
                    </span>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
