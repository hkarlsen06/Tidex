'use client';

import { useState, useId, useRef } from 'react';
import { Label } from '@appui/Label';
import { Button } from '@appui/Button';
import { Input } from '@/components/app/Input';
import { TimeInput } from '@/components/app/TimeInput';
import { Card } from '@appui/Card';
import { Badge } from '@appui/Badge';
import { Trash2, Plus } from 'lucide-react';
import { SupplementRule, SupplementsData } from './types';
import { useTranslations } from '@/lib/i18n/client';

interface SupplementsEditorProps {
  value: SupplementsData | null;
  onChange: (value: SupplementsData | null) => void;
  className?: string;
  readOnly?: boolean;
}

export function SupplementsEditor({
  value,
  onChange,
  className,
  readOnly = false,
}: SupplementsEditorProps) {
  const { t } = useTranslations();
  const baseId = useId();
  const DAY_LABELS = t.dateTime.daysShort.slice(1).concat(t.dateTime.daysShort[0]); // Mon-Sun (reorder from Sun-Sat)
  const createEmptyRule = (id: string): SupplementRule => ({
    id,
    days: [],
    from: '',
    to: '',
  });

  // Initialize with one empty rule if no existing rules, or use existing rules
  const getInitialRules = (): SupplementRule[] => {
    if (value?.rules && value.rules.length > 0) {
      return value.rules.map((rule, index) => {
        // Infer mode from existing data for backward compatibility
        let mode: 'percent' | 'rate' | undefined = rule.mode;
        if (!mode) {
          if (rule.percent !== undefined) {
            mode = 'percent';
          } else if (rule.rate !== undefined) {
            mode = 'rate';
          }
        }
        return {
          ...rule,
          id: `${index}`,
          mode,
        };
      });
    }
    if (readOnly) {
      return [];
    }
    // Start with one empty rule so form is visible
    return [createEmptyRule('0')];
  };

  const [rules, setRules] = useState<SupplementRule[]>(getInitialRules());
  const [nextId, setNextId] = useState(() => rules.length);
  const fromInputRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const toInputRefs = useRef<Record<string, HTMLInputElement | null>>({});

  const addRule = () => {
    if (readOnly) {
      return;
    }
    const newRule = createEmptyRule(`${nextId}`);
    setRules([...rules, newRule]);
    setNextId(nextId + 1);
  };

  const removeRule = (id: string) => {
    if (readOnly) {
      return;
    }
    const newRules = rules.filter((r) => r.id !== id);
    setRules(newRules);
    delete fromInputRefs.current[id];
    delete toInputRefs.current[id];

    // Update parent immediately
    const validRules = newRules.filter(
      (rule) =>
        rule.days.length > 0 &&
        rule.from &&
        rule.to &&
        rule.mode &&
        ((rule.mode === 'percent' && rule.percent !== undefined && rule.percent !== 0) ||
         (rule.mode === 'rate' && rule.rate !== undefined && rule.rate !== 0))
    );

    if (validRules.length > 0) {
      const cleanedRules = validRules.map(({ id: _id, mode: _mode, ...rest }) => rest) as any[];
      onChange({ rules: cleanedRules });
    } else {
      onChange(null);
    }
  };

  const updateRule = (id: string, updates: Partial<SupplementRule>) => {
    if (readOnly) {
      return;
    }
    const newRules = rules.map((r) => (r.id === id ? { ...r, ...updates } : r));
    setRules(newRules);

    // Update parent immediately
    const validRules = newRules.filter(
      (rule) =>
        rule.days.length > 0 &&
        rule.from &&
        rule.to &&
        rule.mode &&
        ((rule.mode === 'percent' && rule.percent !== undefined && rule.percent !== 0) ||
         (rule.mode === 'rate' && rule.rate !== undefined && rule.rate !== 0))
    );

    if (validRules.length > 0) {
      const cleanedRules = validRules.map(({ id: _id, mode: _mode, ...rest }) => rest) as any[];
      onChange({ rules: cleanedRules });
    } else {
      onChange(null);
    }
  };

  const toggleDay = (ruleId: string, day: number) => {
    if (readOnly) {
      return;
    }
    const rule = rules.find((r) => r.id === ruleId);
    if (!rule) return;

    const days = rule.days.includes(day)
      ? rule.days.filter((d) => d !== day)
      : [...rule.days, day].sort();

    updateRule(ruleId, { days });
  };

  // Helper to check if value is invalid
  const isValueInvalid = (rule: SupplementRule) => {
    if (!rule.mode) return false;
    const value = rule.mode === 'percent' ? rule.percent : rule.rate;
    return value === undefined || value === 0;
  };

  return (
    <div className={className}>
      <div className="space-y-4">
        {rules.map((rule) => {
          // Progressive enablement logic
          const hasDays = rule.days.length > 0;
          const hasFromTime = rule.from.length > 0;
          const hasToTime = rule.to.length > 0;
          const hasType = rule.mode === 'percent' || rule.mode === 'rate';

          return (
            <Card key={rule.id} className="p-4 space-y-4 bg-surface-primary">
              <div className="flex items-center justify-between">
                <Badge variant="secondary">
                  {t.components.supplementsEditor.badge.replace('{number}', String(rules.indexOf(rule) + 1))}
                </Badge>
                {!readOnly && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => removeRule(rule.id)}
                    className="h-8 w-8 p-0"
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                )}
              </div>

              {/* Days selector - always enabled */}
              <div className="space-y-2">
                <Label className="text-sm">{t.components.supplementsEditor.daysLabel}</Label>
                <div className="grid grid-cols-4 gap-2">
                  {DAY_LABELS.map((label, idx) => {
                    const dayNum = idx + 1;
                    const isSelected = rule.days.includes(dayNum);
                    return (
                      <button
                        key={dayNum}
                        type="button"
                        onClick={() => toggleDay(rule.id, dayNum)}
                        disabled={readOnly}
                        className={`px-2 py-1.5 text-xs sm:text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                          isSelected
                            ? 'bg-brand-gradientStart text-white border-brand-gradientStart'
                            : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradientStart/50'
                        }`}
                      >
                        {label}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Time range - disabled until days selected */}
              <div
                className={`grid grid-cols-1 gap-3 sm:grid-cols-2 transition-opacity ${
                  !hasDays ? 'opacity-40' : 'opacity-100'
                }`}
              >
                <div className="space-y-2">
                  <Label htmlFor={`${baseId}-from-${rule.id}`} className="text-sm">
                    {t.components.supplementsEditor.fromLabel}
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
                    onChange={(val) => updateRule(rule.id, { from: val })}
                    onComplete={() => {
                      const next = toInputRefs.current[rule.id];
                      if (next) {
                        next.focus();
                      }
                    }}
                    disabled={readOnly || !hasDays}
                    className="w-full"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor={`${baseId}-to-${rule.id}`} className="text-sm">
                    {t.components.supplementsEditor.toLabel}
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
                    onChange={(val) => updateRule(rule.id, { to: val })}
                    disabled={readOnly || !hasDays || !hasFromTime}
                    className="w-full"
                  />
                </div>
              </div>

              {/* Rate or Percent - disabled until times selected */}
              <div
                className={`space-y-2 transition-opacity ${
                  !hasToTime ? 'opacity-40' : 'opacity-100'
                }`}
              >
                <Label className="text-sm">{t.components.supplementsEditor.typeLabel}</Label>
                <div className="flex flex-col gap-2 sm:flex-row">
                  <button
                    type="button"
                    onClick={() =>
                      updateRule(rule.id, { mode: 'percent', percent: undefined, rate: undefined })
                    }
                    disabled={readOnly || !hasToTime}
                    className={`flex-1 px-3 py-2 text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                      rule.mode === 'percent'
                        ? 'bg-brand-gradientStart text-white border-brand-gradientStart'
                        : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradientStart/50'
                    } disabled:hover:border-border`}
                  >
                    {t.components.supplementsEditor.typePercent}
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      updateRule(rule.id, { mode: 'rate', rate: undefined, percent: undefined })
                    }
                    disabled={readOnly || !hasToTime}
                    className={`flex-1 px-3 py-2 text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                      rule.mode === 'rate'
                        ? 'bg-brand-gradientStart text-white border-brand-gradientStart'
                        : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradientStart/50'
                    } disabled:hover:border-border`}
                  >
                    {t.components.supplementsEditor.typeFixed}
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
                    ? rule.mode === 'percent'
                      ? t.components.supplementsEditor.valuePercentLabel
                      : t.components.supplementsEditor.valueFixedLabel
                    : t.components.supplementsEditor.valueLabel}
                </Label>
                <div className="relative">
                  <Input
                    id={`${baseId}-value-${rule.id}`}
                    type="number"
                    min={0}
                    step="any"
                    value={rule.mode === 'percent' ? (rule.percent ?? '') : (rule.rate ?? '')}
                    onChange={(e) => {
                      const inputValue = e.target.value;
                      // Allow empty string (user clearing the field)
                      const val = inputValue === '' ? undefined : parseFloat(inputValue);

                      if (rule.mode === 'percent') {
                        updateRule(rule.id, { percent: val });
                      } else if (rule.mode === 'rate') {
                        updateRule(rule.id, { rate: val });
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
                      {rule.mode === 'percent' ? t.components.supplementsEditor.percentUnit : t.components.supplementsEditor.fixedUnit}
                    </span>
                  )}
                </div>
              </div>
            </Card>
          );
        })}

        {readOnly && rules.length === 0 && (
          <p className="text-sm text-text-secondary italic">
            {t.components.supplementsEditor.noSupplements}
          </p>
        )}

        {!readOnly && (
          <Button
            variant="outline"
            onClick={addRule}
            disabled={rules.some(
              (r) =>
                r.days.length === 0 ||
                !r.from ||
                !r.to ||
                !r.mode ||
                ((r.mode === 'percent' && (r.percent === undefined || r.percent === 0)) ||
                 (r.mode === 'rate' && (r.rate === undefined || r.rate === 0)))
            )}
            className="w-full rounded-3xl"
          >
            <Plus className="h-4 w-4 mr-2" />
            {rules.length === 1 ? t.components.supplementsEditor.addOne : t.components.supplementsEditor.addMultiple}
          </Button>
        )}
      </div>
    </div>
  );
}
