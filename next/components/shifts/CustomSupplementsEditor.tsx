'use client';

import { useState, useId, useRef } from 'react';
import { Label } from '@/components/app/Label';
import { Button } from '@/components/app/Button';
import { Input } from '@/components/app/Input';
import { TimeInput } from '@/components/app/TimeInput';
import { Card } from '@/components/app/Card';
import { Badge } from '@/components/app/Badge';
import { Trash2, Plus } from 'lucide-react';
import type { CustomSupplementsEditorData, CustomSupplementRuleWithId } from '@/lib/custom-supplements/types';
import { useTranslations } from '@/lib/i18n/client';
import { cn } from '@/lib/cn';

interface CustomSupplementsEditorProps {
  value: CustomSupplementsEditorData;
  onChange: (value: CustomSupplementsEditorData) => void;
  className?: string;
  readOnly?: boolean;
}

export function CustomSupplementsEditor({
  value,
  onChange,
  className,
  readOnly = false,
}: CustomSupplementsEditorProps) {
  const { t } = useTranslations();
  const baseId = useId();

  const createEmptyRule = (id: string): CustomSupplementRuleWithId => ({
    id,
    from: '',
    to: '',
    isCustom: true, // New rules are always custom
  });

  const [rules, setRules] = useState<CustomSupplementRuleWithId[]>(() => {
    if (value.rules && value.rules.length > 0) {
      return value.rules.map((rule, index) => {
        // Infer inputMode from existing data
        let inputMode: 'percent' | 'rate' | undefined = rule.inputMode;
        if (!inputMode) {
          if (rule.percent !== undefined) {
            inputMode = 'percent';
          } else if (rule.rate !== undefined) {
            inputMode = 'rate';
          }
        }
        return {
          ...rule,
          id: rule.id || `${index}`,
          inputMode,
        };
      });
    }
    return [];
  });

  const [nextId, setNextId] = useState(() => rules.length + 100);
  const [isAddingNew, setIsAddingNew] = useState(false);
  const [newRule, setNewRule] = useState<CustomSupplementRuleWithId | null>(null);
  const fromInputRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const toInputRefs = useRef<Record<string, HTMLInputElement | null>>({});

  const startAddingRule = () => {
    if (readOnly) return;
    const rule = createEmptyRule(`new-${nextId}`);
    setNewRule(rule);
    setIsAddingNew(true);
    setNextId(nextId + 1);
  };

  const cancelAddingRule = () => {
    setNewRule(null);
    setIsAddingNew(false);
  };

  const confirmAddRule = () => {
    if (!newRule) return;

    // Validate the new rule
    const hasValidTime = newRule.from && newRule.to;
    const hasValidValue =
      (newRule.inputMode === 'percent' && newRule.percent !== undefined && newRule.percent !== 0) ||
      (newRule.inputMode === 'rate' && newRule.rate !== undefined && newRule.rate !== 0);

    if (!hasValidTime || !newRule.inputMode || !hasValidValue) {
      return; // Don't add invalid rule
    }

    const newRules = [...rules, newRule];
    setRules(newRules);
    setNewRule(null);
    setIsAddingNew(false);

    // Update parent
    updateParent(newRules);
  };

  const removeRule = (id: string) => {
    if (readOnly) return;
    const newRules = rules.filter((r) => r.id !== id);
    setRules(newRules);
    delete fromInputRefs.current[id];
    delete toInputRefs.current[id];
    updateParent(newRules);
  };

  const updateRule = (id: string, updates: Partial<CustomSupplementRuleWithId>) => {
    if (readOnly) return;
    const newRules = rules.map((r) => {
      if (r.id !== id) return r;
      // If modifying a tariff supplement, mark it as custom (user has customized it)
      const shouldMarkAsCustom = !r.isCustom && (
        updates.from !== undefined ||
        updates.to !== undefined ||
        updates.inputMode !== undefined ||
        updates.rate !== undefined ||
        updates.percent !== undefined
      );
      return {
        ...r,
        ...updates,
        ...(shouldMarkAsCustom ? { isCustom: true } : {}),
      };
    });
    setRules(newRules);
    updateParent(newRules);
  };

  const updateNewRule = (updates: Partial<CustomSupplementRuleWithId>) => {
    if (!newRule) return;
    setNewRule({ ...newRule, ...updates });
  };

  const updateParent = (currentRules: CustomSupplementRuleWithId[]) => {
    // Filter to valid rules and update parent
    const validRules = currentRules.filter(
      (rule) =>
        rule.from &&
        rule.to &&
        rule.inputMode &&
        ((rule.inputMode === 'percent' && rule.percent !== undefined && rule.percent !== 0) ||
         (rule.inputMode === 'rate' && rule.rate !== undefined && rule.rate !== 0))
    );

    onChange({
      rules: validRules,
    });
  };

  // Helper to check if value is invalid
  const isValueInvalid = (rule: CustomSupplementRuleWithId) => {
    if (!rule.inputMode) return false;
    const val = rule.inputMode === 'percent' ? rule.percent : rule.rate;
    return val === undefined || val === 0;
  };

  // Check if new rule can be confirmed
  const canConfirmNewRule = newRule &&
    newRule.from &&
    newRule.to &&
    newRule.inputMode &&
    ((newRule.inputMode === 'percent' && newRule.percent !== undefined && newRule.percent !== 0) ||
     (newRule.inputMode === 'rate' && newRule.rate !== undefined && newRule.rate !== 0));

  const renderRuleCard = (rule: CustomSupplementRuleWithId, isNew: boolean = false) => {
    const isCustom = rule.isCustom;
    const updateFn = isNew ? updateNewRule : (updates: Partial<CustomSupplementRuleWithId>) => updateRule(rule.id, updates);

    // Progressive enablement logic
    const hasFromTime = rule.from.length > 0;
    const hasToTime = rule.to.length > 0;
    const hasType = rule.inputMode === 'percent' || rule.inputMode === 'rate';

    return (
      <Card
        key={rule.id}
        className={cn(
          "p-4 space-y-4 bg-surface-primary",
          isCustom && "ring-2 ring-blue-500/50"
        )}
      >
        <div className="flex items-center justify-between">
          <Badge variant={isCustom ? "default" : "secondary"} className={cn(isCustom && "bg-blue-600")}>
            {isCustom ? t.components.customSupplementsEditor.customBadge : t.components.customSupplementsEditor.tariffBadge}
          </Badge>
          {!readOnly && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => isNew ? cancelAddingRule() : removeRule(rule.id)}
              className="h-8 w-8 p-0"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>

        {/* Time range */}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor={`${baseId}-from-${rule.id}`} className="text-sm">
              {t.components.customSupplementsEditor.fromLabel}
            </Label>
            <TimeInput
              id={`${baseId}-from-${rule.id}`}
              ref={(el) => {
                if (el) {
                  fromInputRefs.current[rule.id] = el;
                } else {
                  delete fromInputRefs.current[rule.id];
                }
              }}
              value={rule.from}
              onChange={(val) => updateFn({ from: val })}
              onComplete={() => {
                const next = toInputRefs.current[rule.id];
                if (next) next.focus();
              }}
              disabled={readOnly}
              placeholder="00:00"
              className="w-full"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor={`${baseId}-to-${rule.id}`} className="text-sm">
              {t.components.customSupplementsEditor.toLabel}
            </Label>
            <TimeInput
              id={`${baseId}-to-${rule.id}`}
              ref={(el) => {
                if (el) {
                  toInputRefs.current[rule.id] = el;
                } else {
                  delete toInputRefs.current[rule.id];
                }
              }}
              value={rule.to}
              onChange={(val) => updateFn({ to: val })}
              disabled={readOnly || !hasFromTime}
              placeholder="24:00"
              className="w-full"
            />
          </div>
        </div>

        {/* Full Day Quick-fill Button */}
        {!readOnly && (
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => updateFn({ from: '00:00', to: '24:00' })}
            className="w-full text-sm"
          >
            {t.components.customSupplementsEditor.fullDay}
          </Button>
        )}

        {/* Rate or Percent - disabled until times selected */}
        <div
          className={`space-y-2 transition-opacity ${
            !hasToTime ? 'opacity-40' : 'opacity-100'
          }`}
        >
          <Label className="text-sm">{t.components.customSupplementsEditor.typeLabel}</Label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <button
              type="button"
              onClick={() =>
                updateFn({ inputMode: 'percent', percent: undefined, rate: undefined })
              }
              disabled={readOnly || !hasToTime}
              className={`flex-1 px-3 py-2 text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                rule.inputMode === 'percent'
                  ? 'bg-brand-gradient-start text-white border-brand-gradient-start'
                  : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradient-start/50'
              } disabled:hover:border-border`}
            >
              {t.components.customSupplementsEditor.typePercent}
            </button>
            <button
              type="button"
              onClick={() =>
                updateFn({ inputMode: 'rate', rate: undefined, percent: undefined })
              }
              disabled={readOnly || !hasToTime}
              className={`flex-1 px-3 py-2 text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                rule.inputMode === 'rate'
                  ? 'bg-brand-gradient-start text-white border-brand-gradient-start'
                  : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradient-start/50'
              } disabled:hover:border-border`}
            >
              {t.components.customSupplementsEditor.typeFixed}
            </button>
          </div>
        </div>

        {/* Value input - disabled until type selected */}
        <div
          className={`space-y-2 transition-opacity ${
            !hasType ? 'opacity-40' : 'opacity-100'
          }`}
        >
          <Label htmlFor={`${baseId}-value-${rule.id}`} className="text-sm">
            {hasType
              ? rule.inputMode === 'percent'
                ? t.components.customSupplementsEditor.valuePercentLabel
                : t.components.customSupplementsEditor.valueFixedLabel
              : t.components.customSupplementsEditor.valueLabel}
          </Label>
          <div className="relative">
            <Input
              id={`${baseId}-value-${rule.id}`}
              type="number"
              min={0}
              step="any"
              value={rule.inputMode === 'percent' ? (rule.percent ?? '') : (rule.rate ?? '')}
              onChange={(e) => {
                const inputValue = e.target.value;
                const val = inputValue === '' ? undefined : parseFloat(inputValue);

                if (rule.inputMode === 'percent') {
                  updateFn({ percent: val });
                } else if (rule.inputMode === 'rate') {
                  updateFn({ rate: val });
                }
              }}
              onFocus={(e) => e.target.select()}
              disabled={readOnly || !hasType}
              invalid={hasType && isValueInvalid(rule)}
              className={hasType ? 'pr-12' : ''}
              placeholder="0"
            />
            {hasType && (
              <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                {rule.inputMode === 'percent' ? t.components.customSupplementsEditor.percentUnit : t.components.customSupplementsEditor.fixedUnit}
              </span>
            )}
          </div>
        </div>

        {/* Confirm button for new rules */}
        {isNew && (
          <Button
            onClick={confirmAddRule}
            disabled={!canConfirmNewRule}
            className="w-full"
          >
            {t.components.customSupplementsEditor.confirmAdd}
          </Button>
        )}
      </Card>
    );
  };

  return (
    <div className={className}>
      <div className="space-y-4">
        {/* Add Button at the top */}
        {!readOnly && !isAddingNew && (
          <Button
            variant="outline"
            onClick={startAddingRule}
            className="w-full rounded-3xl"
          >
            <Plus className="h-4 w-4 mr-2" />
            {t.components.customSupplementsEditor.addCustom}
          </Button>
        )}

        {/* New rule editor appears at the top */}
        {isAddingNew && newRule && renderRuleCard(newRule, true)}

        {/* Existing rules */}
        {rules.map((rule) => renderRuleCard(rule))}

        {readOnly && rules.length === 0 && (
          <p className="text-sm text-text-secondary italic">
            {t.components.customSupplementsEditor.noSupplements}
          </p>
        )}
      </div>
    </div>
  );
}
