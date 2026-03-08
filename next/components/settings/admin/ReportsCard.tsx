"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import { RefreshCw, Flag, ArrowLeft } from "lucide-react";
import { cn } from "@/lib/cn";

type ReportStatus = "open" | "in_review" | "actioned" | "dismissed";

interface ReportItem {
  id: string;
  reporterUserId: string;
  reporterName: string | null;
  reporterEmail: string | null;
  reportedUserId: string;
  reportedName: string | null;
  reportedEmail: string | null;
  threadId: string;
  messageId: string | null;
  reason: string;
  note: string | null;
  status: ReportStatus;
  reviewerNotes: string | null;
  reviewedAt: string | null;
  reviewedBy: string | null;
  createdAt: string;
}

interface Props {
  refreshTrigger?: number;
}

const STATUS_OPTIONS: ReportStatus[] = ["open", "in_review", "actioned", "dismissed"];

export function ReportsCard({ refreshTrigger }: Props) {
  const [reports, setReports] = useState<ReportItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [offset, setOffset] = useState(0);
  const [selectedReport, setSelectedReport] = useState<ReportItem | null>(null);
  const [statusFilter, setStatusFilter] = useState<ReportStatus | "all">("all");
  const [reviewerNotes, setReviewerNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const limit = 20;

  const searchParams = useMemo(() => {
    const params = new URLSearchParams({
      limit: String(limit),
      offset: String(offset),
    });

    if (statusFilter !== "all") {
      params.set("status", statusFilter);
    }

    return params.toString();
  }, [limit, offset, statusFilter]);

  const fetchReports = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/reports?${searchParams}`);
      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.error ?? "Failed to load reports");
      }

      setReports(result.reports ?? []);
      setTotal(result.total ?? 0);

      if (selectedReport) {
        const updated = (result.reports ?? []).find((item: ReportItem) => item.id === selectedReport.id);
        if (updated) {
          setSelectedReport(updated);
          setReviewerNotes(updated.reviewerNotes ?? "");
        }
      }
    } catch (err) {
      console.error("Failed to fetch reports:", err);
      setError(err instanceof Error ? err.message : "Failed to load reports");
    } finally {
      setLoading(false);
    }
  }, [searchParams, selectedReport]);

  useEffect(() => {
    void fetchReports();
  }, [fetchReports, refreshTrigger]);

  const formatTimestamp = (dateString: string | null) => {
    if (!dateString) return "Not reviewed";
    return new Date(dateString).toLocaleString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  const formatReason = (reason: string) =>
    reason.replaceAll("_", " ").replace(/\b\w/g, (char) => char.toUpperCase());

  const handleSaveStatus = async (status: ReportStatus) => {
    if (!selectedReport) return;

    setSaving(true);
    setSaveError(null);

    try {
      const response = await fetch("/api/admin/reports/status", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          reportId: selectedReport.id,
          status,
          reviewerNotes,
        }),
      });

      const result = await response.json();
      if (!response.ok) {
        throw new Error(result.error ?? "Failed to update report");
      }

      await fetchReports();
    } catch (err) {
      console.error("Failed to update report:", err);
      setSaveError(err instanceof Error ? err.message : "Failed to update report");
    } finally {
      setSaving(false);
    }
  };

  const openDetail = (report: ReportItem) => {
    setSelectedReport(report);
    setReviewerNotes(report.reviewerNotes ?? "");
    setSaveError(null);
  };

  const closeDetail = () => {
    setSelectedReport(null);
    setReviewerNotes("");
    setSaveError(null);
  };

  const hasMore = offset + limit < total;
  const hasPrev = offset > 0;

  if (selectedReport) {
    return (
      <Card className="p-6">
        <div className="flex items-center gap-3 mb-6">
          <Button variant="ghost" size="icon" onClick={closeDetail}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <div>
            <h3 className="text-lg font-semibold">Report Details</h3>
            <p className="text-sm text-text-muted">
              {formatReason(selectedReport.reason)}
            </p>
          </div>
        </div>

        <div className="space-y-6">
          <div className="grid gap-4 md:grid-cols-2">
            <div className="rounded-lg border border-border p-4">
              <div className="text-xs uppercase tracking-wide text-text-muted mb-2">Reporter</div>
              <div className="font-medium text-text-primary">
                {selectedReport.reporterName ?? "Unknown user"}
              </div>
              <div className="text-sm text-text-muted">{selectedReport.reporterEmail ?? "No email"}</div>
              <div className="text-xs text-text-muted mt-2">{selectedReport.reporterUserId}</div>
            </div>

            <div className="rounded-lg border border-border p-4">
              <div className="text-xs uppercase tracking-wide text-text-muted mb-2">Reported User</div>
              <div className="font-medium text-text-primary">
                {selectedReport.reportedName ?? "Unknown user"}
              </div>
              <div className="text-sm text-text-muted">{selectedReport.reportedEmail ?? "No email"}</div>
              <div className="text-xs text-text-muted mt-2">{selectedReport.reportedUserId}</div>
            </div>
          </div>

          <div className="rounded-lg border border-border p-4 space-y-2">
            <div className="flex items-center gap-2 flex-wrap">
              <StatusBadge status={selectedReport.status} />
              <span className="text-sm text-text-muted">
                Created {formatTimestamp(selectedReport.createdAt)}
              </span>
            </div>
            <div className="text-sm text-text-primary">Thread: <span className="font-mono">{selectedReport.threadId}</span></div>
            {selectedReport.messageId && (
              <div className="text-sm text-text-primary">Message: <span className="font-mono">{selectedReport.messageId}</span></div>
            )}
            <div className="text-sm text-text-primary">
              Reviewed: {formatTimestamp(selectedReport.reviewedAt)}
            </div>
          </div>

          {selectedReport.note && (
            <div>
              <h4 className="text-sm font-medium text-text-secondary mb-2">User note</h4>
              <div className="rounded-lg bg-surface-secondary p-4 text-sm whitespace-pre-wrap text-text-primary">
                {selectedReport.note}
              </div>
            </div>
          )}

          <div>
            <h4 className="text-sm font-medium text-text-secondary mb-2">Reviewer notes</h4>
            <textarea
              value={reviewerNotes}
              onChange={(event) => {
                setReviewerNotes(event.target.value);
                setSaveError(null);
              }}
              rows={6}
              disabled={saving}
              className={cn(
                "flex w-full min-w-0 max-w-full rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs transition-colors resize-none",
                "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                "focus:border-ring focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 md:text-sm"
              )}
            />
            {saveError && (
              <p className="mt-2 text-sm text-red-500">{saveError}</p>
            )}
          </div>

          <div className="flex flex-wrap gap-2">
            {STATUS_OPTIONS.map((status) => (
              <Button
                key={status}
                variant={selectedReport.status === status ? "default" : "outline"}
                onClick={() => void handleSaveStatus(status)}
                disabled={saving}
              >
                {saving && selectedReport.status === status ? "Saving..." : formatReason(status)}
              </Button>
            ))}
          </div>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold">Reports</h3>
          <p className="text-sm text-text-muted">
            Review abuse reports from chat and update triage status.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <select
            value={statusFilter}
            onChange={(event) => {
              setOffset(0);
              setStatusFilter(event.target.value as ReportStatus | "all");
            }}
            className="h-10 rounded-md border border-input bg-background px-3 text-sm"
          >
            <option value="all">All statuses</option>
            {STATUS_OPTIONS.map((status) => (
              <option key={status} value={status}>
                {formatReason(status)}
              </option>
            ))}
          </select>

          <Button variant="outline" size="sm" onClick={() => void fetchReports()} disabled={loading}>
            <RefreshCw className={cn("h-4 w-4 mr-2", loading && "animate-spin")} />
            Refresh
          </Button>
        </div>
      </div>

      {error ? (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      ) : loading ? (
        <div className="flex items-center justify-center py-12 text-text-muted">
          <RefreshCw className="h-5 w-5 animate-spin mr-2" />
          Loading reports...
        </div>
      ) : reports.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-3 py-12 text-text-muted">
          <Flag className="h-8 w-8" />
          <p>No reports found</p>
        </div>
      ) : (
        <div className="space-y-3">
          {reports.map((report) => (
            <button
              key={report.id}
              type="button"
              onClick={() => openDetail(report)}
              className="w-full rounded-xl border border-border p-4 text-left transition-colors hover:bg-surface-secondary"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap mb-1">
                    <StatusBadge status={report.status} />
                    <span className="text-sm font-medium text-text-primary">
                      {formatReason(report.reason)}
                    </span>
                  </div>
                  <p className="text-sm text-text-primary">
                    {report.reporterName ?? report.reporterEmail ?? report.reporterUserId}
                    {" -> "}
                    {report.reportedName ?? report.reportedEmail ?? report.reportedUserId}
                  </p>
                  <p className="text-xs text-text-muted mt-1">
                    {formatTimestamp(report.createdAt)}
                  </p>
                  {report.note && (
                    <p className="mt-2 text-sm text-text-secondary line-clamp-2">
                      {report.note}
                    </p>
                  )}
                </div>
              </div>
            </button>
          ))}

          <div className="flex items-center justify-between pt-4">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setOffset((current) => Math.max(0, current - limit))}
              disabled={!hasPrev}
            >
              Previous
            </Button>
            <span className="text-sm text-text-muted">
              {Math.min(offset + 1, total)}-{Math.min(offset + limit, total)} of {total}
            </span>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setOffset((current) => current + limit)}
              disabled={!hasMore}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </Card>
  );
}

function StatusBadge({ status }: { status: ReportStatus }) {
  const classes = {
    open: "bg-amber-100 text-amber-800",
    in_review: "bg-blue-100 text-blue-800",
    actioned: "bg-green-100 text-green-800",
    dismissed: "bg-slate-100 text-slate-700",
  } satisfies Record<ReportStatus, string>;

  return (
    <span className={cn("inline-flex rounded-full px-2 py-0.5 text-xs font-medium", classes[status])}>
      {status.replaceAll("_", " ")}
    </span>
  );
}
