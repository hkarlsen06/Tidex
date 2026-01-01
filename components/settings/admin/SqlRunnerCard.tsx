"use client";

import type React from "react";
import { useState } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import {
  executeSql,
  type SqlResult,
} from "@/app/[locale]/(app)/settings/admin/_actions/executeSql";
import { Play, Database, Clock, AlertTriangle, Copy, Check } from "lucide-react";
import { cn } from "@/lib/cn";

function CopyableCell({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  // Don't show copy button for empty values
  const isEmpty = value === "" || value === "NULL" || value === "undefined";

  return (
    <div className="flex items-center gap-1 group">
      <span className="truncate max-w-xs" title={value}>
        {value}
      </span>
      {!isEmpty && (
        <button
          type="button"
          onClick={handleCopy}
          className="opacity-0 group-hover:opacity-100 transition-opacity p-0.5 hover:bg-surface-secondary rounded shrink-0"
          title="Copy to clipboard"
        >
          {copied ? (
            <Check className="h-3 w-3 text-green-500" />
          ) : (
            <Copy className="h-3 w-3 text-text-muted" />
          )}
        </button>
      )}
    </div>
  );
}

export function SqlRunnerCard() {
  const [query, setQuery] = useState("");
  const [result, setResult] = useState<SqlResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleExecute = async () => {
    if (!query.trim()) {
      setError("Query cannot be empty");
      return;
    }

    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const response = await executeSql(query);
      if (response.success) {
        setResult(response);
      } else {
        setError(response.message);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to execute query");
    } finally {
      setLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Cmd/Ctrl + Enter to execute
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
      e.preventDefault();
      handleExecute();
    }
  };

  const formatValue = (value: unknown): string => {
    if (value === null) return "NULL";
    if (value === undefined) return "undefined";
    if (typeof value === "object") return JSON.stringify(value);
    return String(value);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center gap-2 mb-4">
        <Database className="h-5 w-5 text-text-secondary" />
        <h3 className="text-lg font-semibold">SQL Runner</h3>
      </div>

      <div className="space-y-4">
        {/* Warning */}
        <div className="flex items-start gap-2 p-3 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg">
          <AlertTriangle className="h-4 w-4 text-amber-600 dark:text-amber-500 mt-0.5 shrink-0" />
          <p className="text-sm text-amber-800 dark:text-amber-200">
            This runs with service role privileges and bypasses RLS. Use with caution.
          </p>
        </div>

        {/* Query input */}
        <div>
          <label htmlFor="sql-query" className="block text-sm font-medium text-text-secondary mb-2">
            SQL Query
          </label>
          <textarea
            id="sql-query"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="SELECT * FROM users LIMIT 10;"
            rows={6}
            disabled={loading}
            className={cn(
              "flex w-full min-w-0 max-w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-xs transition-colors resize-y font-mono",
              "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
              "focus:border-ring focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
            )}
          />
          <p className="text-xs text-text-muted mt-1">
            Press Cmd/Ctrl + Enter to execute
          </p>
        </div>

        {/* Execute button */}
        <Button onClick={handleExecute} disabled={loading || !query.trim()}>
          <Play className="h-4 w-4 mr-2" />
          {loading ? "Executing..." : "Execute"}
        </Button>

        {/* Error display */}
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
            <p className="text-sm text-red-800 dark:text-red-200 font-mono whitespace-pre-wrap">
              {error}
            </p>
          </div>
        )}

        {/* Results display */}
        {result && (
          <div className="space-y-2">
            <div className="flex items-center gap-4 text-sm text-text-muted">
              <span>{result.rowCount} row{result.rowCount !== 1 ? "s" : ""} returned</span>
              <span className="flex items-center gap-1">
                <Clock className="h-3 w-3" />
                {result.executionTimeMs}ms
              </span>
            </div>

            {result.data.length > 0 ? (
              <div className="border border-border rounded-lg overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead className="bg-surface-secondary">
                      <tr>
                        {Object.keys(result.data[0]).map((key) => (
                          <th
                            key={key}
                            className="px-3 py-2 text-left font-medium text-text-secondary border-b border-border whitespace-nowrap"
                          >
                            {key}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {result.data.map((row, rowIndex) => (
                        <tr
                          key={rowIndex}
                          className="border-b border-border last:border-b-0 hover:bg-surface-secondary/50"
                        >
                          {Object.values(row).map((value, colIndex) => (
                            <td
                              key={colIndex}
                              className="px-3 py-2 font-mono text-xs whitespace-nowrap"
                            >
                              <CopyableCell value={formatValue(value)} />
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : (
              <div className="text-center py-4 text-text-muted border border-border rounded-lg">
                Query executed successfully (no rows returned)
              </div>
            )}
          </div>
        )}
      </div>
    </Card>
  );
}
