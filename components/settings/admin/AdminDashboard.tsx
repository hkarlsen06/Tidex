"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { SendNotificationCard } from "./SendNotificationCard";
import { NotificationHistoryCard } from "./NotificationHistoryCard";
import { UserListCard } from "./UserListCard";
import { SubscriberListCard } from "./SubscriberListCard";
import { AuditLogCard } from "./AuditLogCard";
import { FeedbackCard } from "./FeedbackCard";
import { SqlRunnerCard } from "./SqlRunnerCard";
import {
  Tabs,
  TabsList,
  TabsTrigger,
  TabsContent,
} from "@/components/app/Tabs";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";

const VALID_TABS = ["notifications", "users", "subscribers", "feedback", "auditlog", "sql"] as const;
type TabValue = (typeof VALID_TABS)[number];

export function AdminDashboard({ dictionary }: { dictionary: Dictionary }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [refreshTrigger, setRefreshTrigger] = useState(0);

  // Get tab from URL or default to "notifications"
  const tabParam = searchParams.get("tab");
  const activeTab: TabValue = VALID_TABS.includes(tabParam as TabValue)
    ? (tabParam as TabValue)
    : "notifications";

  const handleTabChange = (value: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("tab", value);
    router.push(`?${params.toString()}`, { scroll: false });
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Admin Dashboard</h2>
        <p className="text-text-secondary mt-1">
          Manage users, subscriptions, and notifications
        </p>
      </div>

      <Tabs value={activeTab} onValueChange={handleTabChange} className="w-full">
        <div className="overflow-x-auto mb-6">
          <TabsList className="inline-flex w-auto min-w-full">
            <TabsTrigger value="notifications" className="shrink-0">Notifications</TabsTrigger>
            <TabsTrigger value="users" className="shrink-0">Users</TabsTrigger>
            <TabsTrigger value="subscribers" className="shrink-0">Subscribers</TabsTrigger>
            <TabsTrigger value="feedback" className="shrink-0">Feedback</TabsTrigger>
            <TabsTrigger value="auditlog" className="shrink-0">Audit Log</TabsTrigger>
            <TabsTrigger value="sql" className="shrink-0">SQL</TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="notifications" disableAnimation>
          <div className="space-y-6">
            <SendNotificationCard
              dictionary={dictionary}
              onSuccess={() => setRefreshTrigger((n) => n + 1)}
            />
            <NotificationHistoryCard refreshTrigger={refreshTrigger} />
          </div>
        </TabsContent>

        <TabsContent value="users" disableAnimation>
          <UserListCard refreshTrigger={refreshTrigger} />
        </TabsContent>

        <TabsContent value="subscribers" disableAnimation>
          <SubscriberListCard refreshTrigger={refreshTrigger} />
        </TabsContent>

        <TabsContent value="feedback" disableAnimation>
          <FeedbackCard refreshTrigger={refreshTrigger} />
        </TabsContent>

        <TabsContent value="auditlog" disableAnimation>
          <AuditLogCard refreshTrigger={refreshTrigger} />
        </TabsContent>

        <TabsContent value="sql" disableAnimation>
          <SqlRunnerCard />
        </TabsContent>
      </Tabs>
    </div>
  );
}
