"use client";

import { Label } from "@appui/Label";
import { Switch } from "@appui/Switch";
import { Input } from "@appui/Input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@appui/Select";
import { Button } from "@appui/Button";
import { Badge } from "@appui/Badge";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@appui/Tooltip";
import { InfoIcon } from "lucide-react";

interface BreakStepProps {
  breakEnabled: boolean;
  setBreakEnabled: (value: boolean) => void;
  threshold: string;
  setThreshold: (value: string) => void;
  duration: string;
  setDuration: (value: string) => void;
  method: string;
  setMethod: (value: string) => void;
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
  onNext,
  onBack,
}: BreakStepProps) {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold">Pauseinnstillinger</h2>
        <p className="text-text-secondary">Automatisk trekk for lovpålagt pause.</p>
      </div>

      <div className="space-y-6">
        <div className="flex items-center justify-between space-x-2">
          <div className="space-y-0.5">
            <Label htmlFor="break-enabled">Trekk automatisk pause fra vakter</Label>
            <p className="text-sm text-text-muted">
              Anbefalt: Lovpålagt 30 min pause etter 5,5 timer
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
              <Label htmlFor="threshold">Pause trekkes når vakten er lengre enn</Label>
              <div className="relative">
                <Input
                  id="threshold"
                  type="number"
                  step={0.5}
                  min={4}
                  max={8}
                  value={threshold}
                  onChange={(e) => setThreshold(e.target.value)}
                  className="pr-16"
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                  timer
                </span>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="duration">Pauselengde</Label>
              <div className="relative">
                <Input
                  id="duration"
                  type="number"
                  min={15}
                  step={15}
                  value={duration}
                  onChange={(e) => setDuration(e.target.value)}
                  className="pr-20"
                />
                <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                  minutter
                </span>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="method">Hvordan trekkes pausen?</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger id="method">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="proportional">
                    <div className="flex items-center gap-2">
                      <span>Proporsjonal (fordelt over hele vakten)</span>
                      <Badge variant="secondary">Anbefalt</Badge>
                    </div>
                  </SelectItem>
                  <SelectItem value="base_only">
                    Fra grunntid (unngå tillegg)
                  </SelectItem>
                  <SelectItem value="end_of_shift">
                    Fra slutten av vakten
                  </SelectItem>
                  <SelectItem value="none">
                    Ingen automatisk trekk
                  </SelectItem>
                </SelectContent>
              </Select>

              <TooltipProvider>
                <div className="space-y-2 text-sm text-text-muted">
                  <div className="flex items-start gap-2">
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <InfoIcon className="h-4 w-4 mt-0.5 cursor-help" />
                      </TooltipTrigger>
                      <TooltipContent className="max-w-xs">
                        <div className="space-y-2">
                          <p><strong>Proporsjonal:</strong> Pausen fordeles jevnt over hele vakten, inkludert tid med tillegg.</p>
                          <p><strong>Fra grunntid:</strong> Trekker bare fra perioder med grunnlønn (bevarer mest mulig tillegg).</p>
                          <p><strong>Fra slutten:</strong> Trekker fra de siste minuttene av vakten.</p>
                          <p><strong>Ingen trekk:</strong> Du må manuelt registrere pauser i hver vakt.</p>
                        </div>
                      </TooltipContent>
                    </Tooltip>
                    <span>Trykk for å se forklaring av metodene</span>
                  </div>
                </div>
              </TooltipProvider>
            </div>
          </div>
        )}
      </div>

      <div className="flex gap-3">
        <Button onClick={onBack} variant="outline" className="flex-1">
          Tilbake
        </Button>
        <Button onClick={onNext} className="flex-1">
          Neste
        </Button>
      </div>
    </div>
  );
}
