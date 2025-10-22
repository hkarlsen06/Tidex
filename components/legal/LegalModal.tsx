"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/app/Dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/app/Tabs";
import { PrivacyPolicy } from "./PrivacyPolicy";
import { TermsOfService } from "./TermsOfService";

interface LegalModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultTab?: "privacy" | "terms";
}

export function LegalModal({ open, onOpenChange, defaultTab = "terms" }: LegalModalProps) {
  const [activeTab, setActiveTab] = useState(defaultTab);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Juridisk informasjon</DialogTitle>
          <DialogDescription>
            Les gjennom våre vilkår og personvernerklæring
          </DialogDescription>
        </DialogHeader>

        <Tabs value={activeTab} onValueChange={(val) => setActiveTab(val as "privacy" | "terms")} className="flex-1 flex flex-col min-h-0">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="terms">Vilkår for bruk</TabsTrigger>
            <TabsTrigger value="privacy">Personvernerklæring</TabsTrigger>
          </TabsList>

          <TabsContent value="terms" className="flex-1 overflow-y-auto px-1 mt-4">
            <TermsOfService />
          </TabsContent>

          <TabsContent value="privacy" className="flex-1 overflow-y-auto px-1 mt-4">
            <PrivacyPolicy />
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}
