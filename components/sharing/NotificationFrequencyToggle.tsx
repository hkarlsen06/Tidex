"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Bell, BellOff, Clock } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/app/Select";
import { updateNotificationFrequency } from "@/app/[locale]/(app)/sharing/_actions/sharing";
import type { NotificationFrequency } from "@/data-access/sharing";

type NotificationFrequencyToggleProps = {
  sharerId: string;
  currentFrequency: NotificationFrequency;
  disabled?: boolean;
  translations: {
    instant: string;
    summary: string;
    muted: string;
    instantDesc: string;
    summaryDesc: string;
    mutedDesc: string;
  };
  onError?: (error: string) => void;
};

const FREQUENCY_OPTIONS: NotificationFrequency[] = ["instant", "summary", "muted"];

function getFrequencyIcon(frequency: NotificationFrequency) {
  switch (frequency) {
    case "instant":
      return <Bell className="h-4 w-4" />;
    case "summary":
      return <Clock className="h-4 w-4" />;
    case "muted":
      return <BellOff className="h-4 w-4" />;
  }
}

function getFrequencyColor(frequency: NotificationFrequency) {
  switch (frequency) {
    case "instant":
      return "text-brand-gradient-start";
    case "summary":
      return "text-text-secondary";
    case "muted":
      return "text-text-muted";
  }
}

export function NotificationFrequencyToggle({
  sharerId,
  currentFrequency,
  disabled = false,
  translations,
  onError,
}: NotificationFrequencyToggleProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [optimisticFrequency, setOptimisticFrequency] = useState(currentFrequency);

  const handleSelect = (frequency: string) => {
    const freq = frequency as NotificationFrequency;
    if (freq === optimisticFrequency || disabled || isPending) return;

    setOptimisticFrequency(freq);

    startTransition(async () => {
      const result = await updateNotificationFrequency(sharerId, freq);
      if (!result.success) {
        // Revert optimistic update
        setOptimisticFrequency(currentFrequency);
        onError?.(result.error);
        router.refresh();
      }
    });
  };

  const getLabel = (frequency: NotificationFrequency) => {
    switch (frequency) {
      case "instant":
        return translations.instant;
      case "summary":
        return translations.summary;
      case "muted":
        return translations.muted;
    }
  };

  const getDescription = (frequency: NotificationFrequency) => {
    switch (frequency) {
      case "instant":
        return translations.instantDesc;
      case "summary":
        return translations.summaryDesc;
      case "muted":
        return translations.mutedDesc;
    }
  };

  return (
    <Select
      value={optimisticFrequency}
      onValueChange={handleSelect}
      disabled={disabled || isPending}
    >
      <SelectTrigger
        className={`w-auto border-0 bg-transparent p-1.5 h-auto hover:bg-surface-secondary transition-colors ${getFrequencyColor(optimisticFrequency)}`}
        title={getLabel(optimisticFrequency)}
        hideIcon
      >
        <SelectValue>
          {getFrequencyIcon(optimisticFrequency)}
        </SelectValue>
      </SelectTrigger>
      <SelectContent align="end" className="w-56">
        {FREQUENCY_OPTIONS.map((frequency) => (
          <SelectItem
            key={frequency}
            value={frequency}
            className={`flex items-start gap-3 py-2 ${
              frequency === optimisticFrequency ? "bg-surface-secondary" : ""
            }`}
          >
            <div className="flex items-start gap-3 w-full">
              <div className={`mt-0.5 ${getFrequencyColor(frequency)}`}>
                {getFrequencyIcon(frequency)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium text-text-primary">
                  {getLabel(frequency)}
                </div>
                <div className="text-xs text-text-muted">
                  {getDescription(frequency)}
                </div>
              </div>
            </div>
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
