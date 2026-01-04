"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, X, Loader2 } from "lucide-react";
import { Button } from "@/components/app/Button";

interface ImpersonationBannerProps {
  /** Target user being impersonated */
  targetUserName: string | null;
  /** Admin who started the impersonation */
  adminUserId: string;
  /** When the impersonation expires */
  expiresAt: string;
}

export function ImpersonationBanner({
  targetUserName,
  adminUserId: _adminUserId,
  expiresAt,
}: ImpersonationBannerProps) {
  const router = useRouter();
  const [stopping, setStopping] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleStop = async () => {
    setStopping(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/impersonation/stop", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
      });

      const data = await response.json();

      if (!response.ok || !data.ok) {
        // If there's a redirect hint, follow it
        if (data.redirectHint) {
          router.push(data.redirectHint);
          router.refresh();
          return;
        }
        setError(data.error || "Failed to stop impersonation");
        setStopping(false);
        return;
      }

      // Success - refresh and go back to admin users
      router.push("/settings/admin?tab=users");
      router.refresh();
    } catch {
      setError("Network error. Please try again.");
      setStopping(false);
    }
  };

  // Calculate time remaining
  const expiresAtDate = new Date(expiresAt);
  const now = new Date();
  const remainingMs = expiresAtDate.getTime() - now.getTime();
  const remainingMinutes = Math.max(0, Math.floor(remainingMs / 60000));

  return (
    <div className="fixed top-0 left-0 right-0 z-50 bg-amber-500 text-amber-950 px-4 py-2 shadow-md">
      <div className="max-w-7xl mx-auto flex items-center justify-between gap-4">
        <div className="flex items-center gap-2 min-w-0">
          <AlertTriangle className="h-5 w-5 shrink-0" />
          <span className="font-medium truncate">
            Impersonating: <strong>{targetUserName ?? "User"}</strong>
          </span>
          <span className="text-amber-800 text-sm hidden sm:inline">
            ({remainingMinutes} min remaining)
          </span>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          {error && (
            <span className="text-sm text-red-800 hidden sm:inline">{error}</span>
          )}
          <Button
            size="sm"
            variant="outline"
            onClick={handleStop}
            disabled={stopping}
            className="bg-white/90 hover:bg-white text-amber-900 border-amber-700"
          >
            {stopping ? (
              <>
                <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                Stopping...
              </>
            ) : (
              <>
                <X className="h-4 w-4 mr-1" />
                Stop Impersonation
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}
