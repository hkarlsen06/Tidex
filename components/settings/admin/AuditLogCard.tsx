"use client";

import { useState, useEffect, useCallback } from "react";
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
  getAuditLog,
  type AuditLogEntry,
} from "@/app/[locale]/(app)/settings/admin/_actions/getAuditLog";
import {
  ADMIN_ACTIONS,
  ADMIN_ACTION_CONFIG,
  type AdminAction,
} from "@/lib/admin/action-labels";
import { RefreshCw, ChevronDown, ChevronUp, Copy, Check } from "lucide-react";

function CopyableId({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div className="flex items-center gap-1 group">
      <span className="text-text-muted">{label}:</span>
      <code className="ml-1 text-xs">{value.slice(0, 4)}...</code>
      <button
        type="button"
        onClick={handleCopy}
        className="opacity-0 group-hover:opacity-100 transition-opacity p-0.5 hover:bg-background rounded shrink-0"
        title={`Copy full ID: ${value}`}
      >
        {copied ? (
          <Check className="h-3 w-3 text-green-500" />
        ) : (
          <Copy className="h-3 w-3 text-text-muted" />
        )}
      </button>
    </div>
  );
}

interface Props {
  refreshTrigger?: number;
}

export function AuditLogCard({ refreshTrigger }: Props) {
  const [entries, setEntries] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionFilter, setActionFilter] = useState<AdminAction | "all">("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const fetchAuditLog = useCallback(async () => {
    setLoading(true);
    setError(null);
    const result = await getAuditLog({
      limit: 100,
      actionFilter: actionFilter === "all" ? undefined : actionFilter,
    });
    if (result.success) {
      setEntries(result.entries);
    } else {
      setError(result.message);
    }
    setLoading(false);
  }, [actionFilter]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    fetchAuditLog();
  }, [fetchAuditLog, refreshTrigger]);

  const formatTimestamp = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString("en-US", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  const getSeverityVariant = (
    action: AdminAction
  ): "default" | "secondary" | "outline" | "destructive" => {
    const config = ADMIN_ACTION_CONFIG[action];
    if (!config) return "outline";
    switch (config.severity) {
      case "destructive":
        return "destructive";
      case "warning":
        return "secondary";
      default:
        return "outline";
    }
  };

  const formatMetadata = (metadata: Record<string, unknown>): string => {
    if (Object.keys(metadata).length === 0) return "";
    return JSON.stringify(metadata, null, 2);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Audit Log</h3>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="icon"
            onClick={fetchAuditLog}
            disabled={loading}
          >
            <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          </Button>
          <Select
            value={actionFilter}
            onValueChange={(v) => setActionFilter(v as AdminAction | "all")}
          >
            <SelectTrigger className="w-36">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All actions</SelectItem>
              {ADMIN_ACTIONS.map((action) => (
                <SelectItem key={action} value={action}>
                  {ADMIN_ACTION_CONFIG[action].label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      {error && <p className="text-red-600 mb-4">{error}</p>}

      {loading ? (
        <div className="text-center py-8 text-text-muted">Loading...</div>
      ) : entries.length === 0 ? (
        <div className="text-center py-8 text-text-muted">
          No activity found
        </div>
      ) : (
        <div className="space-y-2">
          {entries.map((entry) => (
            <div
              key={entry.id}
              className="border border-border rounded-lg overflow-hidden"
            >
              <button
                type="button"
                className="flex items-center justify-between p-3 cursor-pointer hover:bg-surface-secondary/50 w-full text-left"
                onClick={() =>
                  setExpandedId(expandedId === entry.id ? null : entry.id)
                }
              >
                <div className="flex items-center gap-3 flex-1 min-w-0">
                  <Badge variant={getSeverityVariant(entry.action)}>
                    {ADMIN_ACTION_CONFIG[entry.action]?.label ?? entry.action}
                  </Badge>
                  <span className="text-sm text-text-secondary truncate">
                    {entry.adminEmail}
                    {entry.targetEmail && (
                      <>
                        {" → "}
                        <span className="text-text-primary">
                          {entry.targetEmail}
                        </span>
                      </>
                    )}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-text-muted whitespace-nowrap">
                    {formatTimestamp(entry.createdAt)}
                  </span>
                  {expandedId === entry.id ? (
                    <ChevronUp className="h-4 w-4 text-text-muted" />
                  ) : (
                    <ChevronDown className="h-4 w-4 text-text-muted" />
                  )}
                </div>
              </button>

              {expandedId === entry.id && (
                <div className="px-3 pb-3 pt-0">
                  <div className="bg-surface-secondary rounded p-3 text-sm space-y-2">
                    <div className="grid grid-cols-2 gap-2">
                      {entry.adminId && (
                        <CopyableId label="Admin ID" value={entry.adminId} />
                      )}
                      {entry.targetUserId && (
                        <CopyableId label="Target ID" value={entry.targetUserId} />
                      )}
                    </div>
                    {Object.keys(entry.metadata).length > 0 && (
                      <div>
                        <span className="text-text-muted block mb-1">
                          Metadata:
                        </span>
                        <pre className="text-xs bg-background rounded p-2 overflow-x-auto">
                          {formatMetadata(entry.metadata)}
                        </pre>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
