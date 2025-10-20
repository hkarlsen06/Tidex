"use client";

import { MutableRefObject, useCallback, useEffect, useRef, useState } from "react";
import { Label } from "@appui/Label";
import { Switch } from "@appui/Switch";
import { Input } from "@appui/Input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@appui/Select";
import { Button } from "@appui/Button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@appui/Tooltip";
import { InfoIcon } from "lucide-react";
import { IconArrowNarrowDown } from "@tabler/icons-react";
import { cn } from "@/lib/utils";

interface ArrowButtonConfig {
  available: boolean;
  activated: boolean;
  pressed: boolean;
}

const arrowButtonClasses = ({ available, activated, pressed }: ArrowButtonConfig) =>
  cn(
    "flex h-9 w-9 items-center justify-center rounded-md border border-border transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background touch-manipulation",
    available
      ? activated
        ? "cursor-default bg-surface-secondary text-text-secondary opacity-70"
        : "cursor-pointer bg-black text-white shadow-sm hover:opacity-90 dark:bg-white dark:text-black"
      : "cursor-not-allowed bg-surface-secondary text-text-muted opacity-40",
    pressed && "opacity-70"
  );

const triggerPressFeedback = (
  setPressed: (value: boolean) => void,
  timeoutRef: MutableRefObject<ReturnType<typeof setTimeout> | null>
) => {
  setPressed(true);
  if (timeoutRef.current) {
    clearTimeout(timeoutRef.current);
  }
  timeoutRef.current = setTimeout(() => {
    setPressed(false);
  }, 400);
};

interface BreakStepProps {
  breakEnabled: boolean;
  setBreakEnabled: (value: boolean) => void;
  threshold: string;
  setThreshold: (value: string) => void;
  duration: string;
  setDuration: (value: string) => void;
  method: string;
  setMethod: (value: string) => void;
  thresholdActivated: boolean;
  setThresholdActivated: (value: boolean) => void;
  durationActivated: boolean;
  setDurationActivated: (value: boolean) => void;
  methodActivated: boolean;
  setMethodActivated: (value: boolean) => void;
  onNext: () => void;
  onBack: () => void;
}

export function BreakStep({
  breakEnabled,
  setBreakEnabled,
  threshold,
  setThreshold,
  duration,
  setDuration,
  method,
  setMethod,
  thresholdActivated,
  setThresholdActivated,
  durationActivated,
  setDurationActivated,
  methodActivated,
  setMethodActivated,
  onNext,
  onBack,
}: BreakStepProps) {
  const [tooltipOpen, setTooltipOpen] = useState(false);
  const [thresholdButtonPressed, setThresholdButtonPressed] = useState(false);
  const [durationButtonPressed, setDurationButtonPressed] = useState(false);
  const [methodButtonPressed, setMethodButtonPressed] = useState(false);

  const thresholdButtonTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);
  const durationButtonTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);
  const methodButtonTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleThresholdButtonPress = () => {
    setThresholdActivated(true);
    triggerPressFeedback(setThresholdButtonPressed, thresholdButtonTimeout);
  };

  const handleDurationButtonPress = () => {
    if (!thresholdActivated) {
      return;
    }
    setDurationActivated(true);
    triggerPressFeedback(setDurationButtonPressed, durationButtonTimeout);
  };

  const handleMethodButtonPress = () => {
    if (!durationActivated) {
      return;
    }
    setMethodActivated(true);
    triggerPressFeedback(setMethodButtonPressed, methodButtonTimeout);
  };

  const clearAllTimeouts = useCallback(() => {
    if (thresholdButtonTimeout.current) {
      clearTimeout(thresholdButtonTimeout.current);
      thresholdButtonTimeout.current = null;
    }
    if (durationButtonTimeout.current) {
      clearTimeout(durationButtonTimeout.current);
      durationButtonTimeout.current = null;
    }
    if (methodButtonTimeout.current) {
      clearTimeout(methodButtonTimeout.current);
      methodButtonTimeout.current = null;
    }
  }, [durationButtonTimeout, methodButtonTimeout, thresholdButtonTimeout]);

  useEffect(() => clearAllTimeouts, [clearAllTimeouts]);

  const isFormComplete =
    !breakEnabled || (thresholdActivated && durationActivated && methodActivated);
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">Pauseinnstillinger</h2>
        <p className="text-text-secondary">Automatisk trekk for lovpålagte pauser</p>
      </div>

      <div className="space-y-6">
        <div className="flex items-center justify-between space-x-2">
          <div className="space-y-0.5">
            <Label htmlFor="break-enabled">Pausetrekk</Label>
            <p className="text-sm text-text-muted">
              {breakEnabled ? (
                <>Jeg får <span className="underline">ikke</span> betalt for pauser</>
              ) : (
                <>Jeg <span className="underline">får</span> betalt for pauser</>
              )}
            </p>
          </div>
          <Switch
            id="break-enabled"
            checked={breakEnabled}
            onCheckedChange={setBreakEnabled}
          />
        </div>

        {breakEnabled && (
          <div className="space-y-4 pt-4 border-t border-border">
            <div className="space-y-2">
              <Label htmlFor="threshold">Jeg får pause når vakten er lengre enn</Label>
              <div className="flex items-stretch gap-2">
                <div className="relative flex-1">
                  <Input
                    id="threshold"
                    type="number"
                    step={0.5}
                    min={4}
                    max={8}
                    value={threshold}
                    onChange={(e) => setThreshold(e.target.value)}
                    onFocus={() => setThresholdActivated(true)}
                    className="pr-16"
                  />
                  <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                    timer
                  </span>
                </div>
                <button
                  type="button"
                  onClick={handleThresholdButtonPress}
                  aria-label="Aktiver feltet for lengde før pause"
                  className={arrowButtonClasses({
                    available: true,
                    activated: thresholdActivated,
                    pressed: thresholdButtonPressed,
                  })}
                >
                  <IconArrowNarrowDown stroke={2} className="h-4 w-4" />
                </button>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="duration" className={!thresholdActivated ? "opacity-40" : ""}>
                Pausene mine er på
              </Label>
              <div className="flex items-stretch gap-2">
                <div className="relative flex-1">
                  <Input
                    id="duration"
                    type="number"
                    min={15}
                    step={15}
                    value={duration}
                    onChange={(e) => setDuration(e.target.value)}
                    onFocus={() => setDurationActivated(true)}
                    disabled={!thresholdActivated}
                    className="pr-20"
                  />
                  <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                    minutter
                  </span>
                </div>
                <button
                  type="button"
                  onClick={handleDurationButtonPress}
                  aria-label="Aktiver feltet for pausens lengde"
                  disabled={!thresholdActivated}
                  className={arrowButtonClasses({
                    available: thresholdActivated,
                    activated: durationActivated,
                    pressed: durationButtonPressed,
                  })}
                >
                  <IconArrowNarrowDown stroke={2} className="h-4 w-4" />
                </button>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="method" className={!durationActivated ? "opacity-40" : ""}>
                Hvordan trekkes pausen?
              </Label>
              <div className="flex items-stretch gap-2">
                <Select
                  value={method}
                  onValueChange={(value) => {
                    setMethod(value);
                    setMethodActivated(true);
                    triggerPressFeedback(setMethodButtonPressed, methodButtonTimeout);
                  }}
                  disabled={!durationActivated}
                >
                  <SelectTrigger id="method" disabled={!durationActivated}>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="proportional">
                      Proporsjonal (anbefalt)
                    </SelectItem>
                    <SelectItem value="base_only">
                      Fra grunnlønn
                    </SelectItem>
                    <SelectItem value="end_of_shift">
                      Fra slutten av vakten
                    </SelectItem>
                  </SelectContent>
                </Select>
                <button
                  type="button"
                  onClick={handleMethodButtonPress}
                  aria-label="Aktiver valg for pausemetode"
                  disabled={!durationActivated}
                  className={arrowButtonClasses({
                    available: durationActivated,
                    activated: methodActivated,
                    pressed: methodButtonPressed,
                  })}
                >
                  <IconArrowNarrowDown stroke={2} className="h-4 w-4" />
                </button>
              </div>

              <div className="space-y-2 text-sm text-text-muted">
                <Tooltip open={tooltipOpen} onOpenChange={setTooltipOpen} delayDuration={0}>
                  <TooltipTrigger
                    asChild
                    onPointerDown={(e) => e.preventDefault()}
                  >
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        setTooltipOpen(!tooltipOpen);
                      }}
                      className="flex items-start gap-2 cursor-pointer hover:text-text-primary transition-colors text-left touch-manipulation"
                    >
                      <InfoIcon className="h-4 w-4 mt-0.5" />
                      <span>Se forklaring av metodene</span>
                    </button>
                  </TooltipTrigger>
                  <TooltipContent
                    className="max-w-xs bg-surface-primary border-border text-text-primary"
                    onPointerDownOutside={() => setTooltipOpen(false)}
                    onEscapeKeyDown={() => setTooltipOpen(false)}
                  >
                    <div className="space-y-2">
                      <p><strong>Proporsjonal:</strong> Pausen fordeles jevnt over hele vakten, inkludert tid med tillegg.</p>
                      <p><strong>Fra grunnlønn:</strong> Trekker bare fra perioder med grunnlønn (bevarer mest mulig tillegg).</p>
                      <p><strong>Fra slutten:</strong> Trekker fra de siste minuttene av vakten.</p>
                    </div>
                  </TooltipContent>
                </Tooltip>
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          Tilbake
        </Button>
        <Button onClick={onNext} className="flex-1" disabled={!isFormComplete}>
          Neste
        </Button>
      </div>
    </div>
  );
}
