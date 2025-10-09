"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@appui/Dialog";
import { Button } from "@appui/Button";

interface OnboardingPromptModalProps {
  shouldShow: boolean;
}

export function OnboardingPromptModal({ shouldShow }: OnboardingPromptModalProps) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Check if user has already dismissed this session
    const hasSeenPrompt = sessionStorage.getItem("onboarding_prompt_dismissed");

    if (shouldShow && !hasSeenPrompt && !dismissed) {
      // Small delay to avoid jarring immediate popup
      const timer = setTimeout(() => {
        setOpen(true);
      }, 500);
      return () => clearTimeout(timer);
    }
  }, [shouldShow, dismissed]);

  const handleSetup = () => {
    setOpen(false);
    router.push("/onboarding");
  };

  const handleDismiss = () => {
    setOpen(false);
    setDismissed(true);
    sessionStorage.setItem("onboarding_prompt_dismissed", "true");
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Fullfør kontooppsettet</DialogTitle>
          <DialogDescription className="pt-2">
            Fullfør den raske innstillingen for å få riktige lønnsberegninger og automatiske
            pausetrekk. Det tar bare 2 minutter!
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-4">
          <div className="flex items-start gap-3">
            <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand-gradientStart/10 text-brand-gradientStart">
              <span className="text-sm font-semibold">1</span>
            </div>
            <div className="space-y-1">
              <p className="text-sm font-medium">Velg lønnsoppsett</p>
              <p className="text-sm text-text-muted">Tariff eller egendefinert timelønn</p>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand-gradientStart/10 text-brand-gradientStart">
              <span className="text-sm font-semibold">2</span>
            </div>
            <div className="space-y-1">
              <p className="text-sm font-medium">Konfigurer pausetrekk</p>
              <p className="text-sm text-text-muted">Automatisk lovpålagt pause</p>
            </div>
          </div>

          <div className="flex items-start gap-3">
            <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand-gradientStart/10 text-brand-gradientStart">
              <span className="text-sm font-semibold">3</span>
            </div>
            <div className="space-y-1">
              <p className="text-sm font-medium">Tilpass preferanser</p>
              <p className="text-sm text-text-muted">Tema, visning og mål</p>
            </div>
          </div>
        </div>

        <DialogFooter className="sm:space-x-2">
          <Button variant="outline" onClick={handleDismiss}>
            Gjør det senere
          </Button>
          <Button onClick={handleSetup}>
            Start oppsett
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
