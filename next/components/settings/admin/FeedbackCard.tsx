"use client";

import { useState, useEffect, useCallback } from "react";
import { Card } from "@/components/app/Card";
import { Button } from "@/components/app/Button";
import {
  getFeedback,
  type FeedbackItem,
} from "@/app/[locale]/(app)/settings/admin/_actions/getFeedback";
import { respondToFeedback } from "@/app/[locale]/(app)/settings/admin/_actions/respondToFeedback";
import {
  RefreshCw,
  MessageSquare,
  CheckCircle2,
  Send,
  User,
  ArrowLeft,
  Clock,
} from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/app/Avatar";
import { cn } from "@/lib/cn";

interface Props {
  refreshTrigger?: number;
}

export function FeedbackCard({ refreshTrigger }: Props) {
  const [feedback, setFeedback] = useState<FeedbackItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [offset, setOffset] = useState(0);
  const [selectedItem, setSelectedItem] = useState<FeedbackItem | null>(null);
  const [responseText, setResponseText] = useState("");
  const [submittingResponse, setSubmittingResponse] = useState(false);
  const [responseError, setResponseError] = useState<string | null>(null);
  const [isEditing, setIsEditing] = useState(false);
  const limit = 20;

  const fetchFeedback = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await getFeedback(limit, offset);
      setFeedback(result.feedback);
      setTotal(result.total);
      // Update selected item if it exists in the new data
      if (selectedItem) {
        const updated = result.feedback.find((f) => f.id === selectedItem.id);
        if (updated) {
          setSelectedItem(updated);
        }
      }
    } catch (err) {
      console.error("Failed to fetch feedback:", err);
      setError("Failed to load feedback");
    } finally {
      setLoading(false);
    }
  }, [offset, selectedItem]);

  useEffect(() => {
     
    fetchFeedback();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [offset, refreshTrigger]);

  const formatTimestamp = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  const truncateMessage = (message: string, maxLength = 80) => {
    if (message.length <= maxLength) return message;
    return message.slice(0, maxLength) + "...";
  };

  const handleSubmitResponse = async () => {
    if (!selectedItem || !responseText.trim()) {
      setResponseError("Response cannot be empty");
      return;
    }

    setSubmittingResponse(true);
    setResponseError(null);

    try {
      await respondToFeedback(selectedItem.id, responseText);
      await fetchFeedback();
      setIsEditing(false);
      setResponseText("");
    } catch (err) {
      console.error("Failed to submit response:", err);
      setResponseError("Failed to submit response");
    } finally {
      setSubmittingResponse(false);
    }
  };

  const openDetail = (item: FeedbackItem) => {
    setSelectedItem(item);
    setResponseText("");
    setResponseError(null);
    setIsEditing(false);
  };

  const closeDetail = () => {
    setSelectedItem(null);
    setResponseText("");
    setResponseError(null);
    setIsEditing(false);
  };

  const startEditing = () => {
    setIsEditing(true);
    setResponseText(selectedItem?.response ?? "");
  };

  const cancelEditing = () => {
    setIsEditing(false);
    setResponseText("");
    setResponseError(null);
  };

  const hasMore = offset + limit < total;
  const hasPrev = offset > 0;

  // Detail view for selected feedback
  if (selectedItem) {
    return (
      <Card className="p-6">
        {/* Header with back button */}
        <div className="flex items-center gap-3 mb-6">
          <Button variant="ghost" size="icon" onClick={closeDetail}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <h3 className="text-lg font-semibold">Feedback Details</h3>
        </div>

        <div className="space-y-6">
          {/* User info */}
          <div className="flex items-start gap-3">
            <Avatar className="h-11 w-11 shrink-0">
              <AvatarImage
                src={selectedItem.user_profile_picture ?? undefined}
                alt={selectedItem.user_name || "User"}
              />
              <AvatarFallback>
                <User className="h-5 w-5 text-text-muted" />
              </AvatarFallback>
            </Avatar>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-medium text-text-primary">
                  {selectedItem.user_name || "Anonymous User"}
                </span>
                {selectedItem.response && (
                  <span className="inline-flex items-center gap-1 text-xs text-green-600 bg-green-50 dark:bg-green-900/20 px-2 py-0.5 rounded-full">
                    <CheckCircle2 className="h-3 w-3" />
                    Responded
                  </span>
                )}
              </div>
              <p className="text-sm text-text-muted truncate">
                {selectedItem.user_email}
              </p>
              <p className="text-xs text-text-muted mt-0.5">
                {formatTimestamp(selectedItem.created_at)}
              </p>
            </div>
          </div>

          {/* User's message */}
          <div>
            <h4 className="text-sm font-medium text-text-secondary mb-2">
              Message
            </h4>
            <div className="bg-surface-secondary rounded-lg p-4">
              <p className="text-sm whitespace-pre-wrap text-text-primary">
                {selectedItem.message}
              </p>
            </div>
          </div>

          {/* Response section */}
          <div>
            <h4 className="text-sm font-medium text-text-secondary mb-2">
              Response
            </h4>

            {selectedItem.response && !isEditing ? (
              <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2 text-sm text-green-600 dark:text-green-500">
                    <Clock className="h-4 w-4" />
                    <span>
                      {selectedItem.responded_at
                        ? formatTimestamp(selectedItem.responded_at)
                        : ""}
                    </span>
                  </div>
                  <Button variant="ghost" size="sm" onClick={startEditing}>
                    Edit
                  </Button>
                </div>
                <p className="text-sm whitespace-pre-wrap text-green-800 dark:text-green-200">
                  {selectedItem.response}
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                <textarea
                  value={responseText}
                  onChange={(e) => {
                    setResponseText(e.target.value);
                    setResponseError(null);
                  }}
                  placeholder="Write your response..."
                  rows={6}
                  disabled={submittingResponse}
                  className={cn(
                    "flex w-full min-w-0 max-w-full rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs transition-colors resize-none",
                    "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                    "focus:border-ring focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 md:text-sm"
                  )}
                />
                {responseError && (
                  <p className="text-sm text-red-500">{responseError}</p>
                )}
                <div className="flex items-center gap-2">
                  <Button
                    onClick={handleSubmitResponse}
                    disabled={submittingResponse || !responseText.trim()}
                  >
                    <Send className="h-4 w-4 mr-2" />
                    {submittingResponse ? "Sending..." : "Send Response"}
                  </Button>
                  {isEditing && (
                    <Button
                      variant="ghost"
                      onClick={cancelEditing}
                      disabled={submittingResponse}
                    >
                      Cancel
                    </Button>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      </Card>
    );
  }

  // List view
  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <MessageSquare className="h-5 w-5 text-text-secondary" />
          <h3 className="text-lg font-semibold">User Feedback</h3>
          {total > 0 && (
            <span className="text-sm text-text-muted">({total} total)</span>
          )}
        </div>
        <Button
          variant="ghost"
          size="icon"
          onClick={fetchFeedback}
          disabled={loading}
        >
          <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
        </Button>
      </div>

      {error && <p className="text-red-600 mb-4">{error}</p>}

      {loading ? (
        <div className="text-center py-8 text-text-muted">Loading...</div>
      ) : feedback.length === 0 ? (
        <div className="text-center py-8 text-text-muted">
          No feedback received yet
        </div>
      ) : (
        <>
          <div className="space-y-2">
            {feedback.map((item) => (
              <button
                type="button"
                key={item.id}
                onClick={() => openDetail(item)}
                className="w-full text-left border border-border rounded-lg p-3 hover:bg-surface-secondary/50 transition-colors cursor-pointer"
              >
                <div className="flex items-start gap-3">
                  <Avatar className="h-10 w-10 shrink-0">
                    <AvatarImage
                      src={item.user_profile_picture ?? undefined}
                      alt={item.user_name || "User"}
                    />
                    <AvatarFallback>
                      <User className="h-4 w-4 text-text-muted" />
                    </AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2 mb-0.5">
                      <div className="flex items-center gap-2 min-w-0">
                        <span className="font-medium text-text-primary text-sm truncate">
                          {item.user_name || "Anonymous User"}
                        </span>
                        {item.response ? (
                          <span className="inline-flex items-center gap-1 text-xs text-green-600 bg-green-50 dark:bg-green-900/20 px-1.5 py-0.5 rounded-full shrink-0">
                            <CheckCircle2 className="h-3 w-3" />
                            Responded
                          </span>
                        ) : (
                          <span className="inline-flex items-center text-xs text-amber-600 bg-amber-50 dark:bg-amber-900/20 px-1.5 py-0.5 rounded-full shrink-0">
                            Awaiting
                          </span>
                        )}
                      </div>
                      <span className="text-xs text-text-muted shrink-0 hidden sm:block">
                        {formatTimestamp(item.created_at)}
                      </span>
                    </div>
                    <p className="text-sm text-text-muted truncate">
                      {truncateMessage(item.message)}
                    </p>
                    <p className="text-xs text-text-muted mt-1 sm:hidden">
                      {formatTimestamp(item.created_at)}
                    </p>
                  </div>
                </div>
              </button>
            ))}
          </div>

          {/* Pagination */}
          {(hasMore || hasPrev) && (
            <div className="flex items-center justify-between mt-4 pt-4 border-t border-border">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setOffset(Math.max(0, offset - limit))}
                disabled={!hasPrev || loading}
              >
                Previous
              </Button>
              <span className="text-sm text-text-muted">
                {offset + 1}-{Math.min(offset + limit, total)} of {total}
              </span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setOffset(offset + limit)}
                disabled={!hasMore || loading}
              >
                Next
              </Button>
            </div>
          )}
        </>
      )}
    </Card>
  );
}
