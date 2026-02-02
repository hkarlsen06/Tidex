"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/app/Dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/app/Tabs";
import { Button } from "@/components/app/Button";
import { PrivacyPolicy } from "./PrivacyPolicy";
import { TermsOfService } from "./TermsOfService";
import { useTranslations } from "@/lib/i18n/client";

interface LegalModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultTab?: "privacy" | "terms";
  onAccept?: () => void;
  onDecline?: () => void;
  showActions?: boolean;
}

export function LegalModal({
  open,
  onOpenChange,
  defaultTab = "terms",
  onAccept,
  onDecline,
  showActions = false
}: LegalModalProps) {
  const [activeTab, setActiveTab] = useState(defaultTab);
  const { t } = useTranslations();

  const handleAccept = () => {
    onAccept?.();
    onOpenChange(false);
  };

  const handleDecline = () => {
    onDecline?.();
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>{t.legal.modalTitle}</DialogTitle>
          <DialogDescription>
            {t.legal.modalDescription}
          </DialogDescription>
        </DialogHeader>

        <Tabs value={activeTab} onValueChange={(val) => setActiveTab(val as "privacy" | "terms")} className="flex-1 flex flex-col min-h-0">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="terms">{t.legal.tabs.terms}</TabsTrigger>
            <TabsTrigger value="privacy">{t.legal.tabs.privacy}</TabsTrigger>
          </TabsList>

          <TabsContent value="terms" className="flex-1 overflow-y-auto px-1 mt-4">
            <TermsOfService content={t.legal.terms} />
          </TabsContent>

          <TabsContent value="privacy" className="flex-1 overflow-y-auto px-1 mt-4">
            <PrivacyPolicy content={t.legal.privacy} />
          </TabsContent>
        </Tabs>

        {showActions && (
          <DialogFooter className="gap-2 sm:gap-0">
            <Button
              variant="outline"
              onClick={handleDecline}
            >
              {t.legal.actions.decline}
            </Button>
            <Button
              onClick={handleAccept}
            >
              {t.legal.actions.accept}
            </Button>
          </DialogFooter>
        )}
      </DialogContent>
    </Dialog>
  );
}
