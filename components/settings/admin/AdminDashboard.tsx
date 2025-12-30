"use client";

import { useState } from "react";
import { SendNotificationCard } from "./SendNotificationCard";
import { NotificationHistoryCard } from "./NotificationHistoryCard";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";

export function AdminDashboard({ dictionary }: { dictionary: Dictionary }) {
  const [refreshTrigger, setRefreshTrigger] = useState(0);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Admin Dashboard</h2>
        <p className="text-text-secondary mt-1">
          Send push notifications and view broadcast history
        </p>
      </div>

      <SendNotificationCard
        dictionary={dictionary}
        onSuccess={() => setRefreshTrigger((n) => n + 1)}
      />

      <NotificationHistoryCard refreshTrigger={refreshTrigger} />
    </div>
  );
}
