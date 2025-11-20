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
  });

  const [rules, setRules] = useState<CustomSupplementRuleWithId[]>(() => {
    if (value.rules && value.rules.length > 0) {
      return value.rules.map((rule, index) => {
        // Infer mode from existing data
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
          id: rule.id || `${index}`,
          mode,
        };
      });
    }
    if (readOnly) {
      return [];
    }
    // Start with one empty rule
    return [createEmptyRule('0')];
  });

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
        rule.from &&
        rule.to &&
        rule.mode &&
        ((rule.mode === 'percent' && rule.percent !== undefined && rule.percent !== 0) ||
         (rule.mode === 'rate' && rule.rate !== undefined && rule.rate !== 0))
    );

    onChange({
      mode: value.mode,
      rules: validRules.map(({ id: _id, mode: _mode, ...rest }) => rest) as any[],
    });
  };

  const updateRule = (id: string, updates: Partial<CustomSupplementRuleWithId>) => {
    if (readOnly) {
      return;
    }
    const newRules = rules.map((r) => (r.id === id ? { ...r, ...updates } : r));
    setRules(newRules);

    // Update parent immediately
    const validRules = newRules.filter(
      (rule) =>
        rule.from &&
        rule.to &&
        rule.mode &&
        ((rule.mode === 'percent' && rule.percent !== undefined && rule.percent !== 0) ||
         (rule.mode === 'rate' && rule.rate !== undefined && rule.rate !== 0))
    );

    onChange({
      mode: value.mode,
      rules: validRules.map(({ id: _id, mode: _mode, ...rest }) => rest) as any[],
    });
  };

  // Helper to check if value is invalid
  const isValueInvalid = (rule: CustomSupplementRuleWithId) => {
    if (!rule.mode) return false;
    const val = rule.mode === 'percent' ? rule.percent : rule.rate;
    return val === undefined || val === 0;
  };

  return (
    <div className={className}>
      <div className="space-y-4">
        {rules.map((rule) => {
          // Progressive enablement logic
          const hasFromTime = rule.from.length > 0;
          const hasToTime = rule.to.length > 0;
          const hasType = rule.mode === 'percent' || rule.mode === 'rate';

          return (
            <Card key={rule.id} className="p-4 space-y-4 bg-surface-primary">
              <div className="flex items-center justify-between">
                <Badge variant="secondary">
                  {t.components.customSupplementsEditor.badge.replace('{number}', String(rules.indexOf(rule) + 1))}
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
                    onChange={(val) => updateRule(rule.id, { from: val })}
                    onComplete={() => {
                      const next = toInputRefs.current[rule.id];
                      if (next) {
                        next.focus();
                      }
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
                    onChange={(val) => updateRule(rule.id, { to: val })}
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
                  onClick={() => updateRule(rule.id, { from: '00:00', to: '24:00' })}
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
                      updateRule(rule.id, { mode: 'percent', percent: undefined, rate: undefined })
                    }
                    disabled={readOnly || !hasToTime}
                    className={`flex-1 px-3 py-2 text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                      rule.mode === 'percent'
                        ? 'bg-brand-gradient-start text-white border-brand-gradient-start'
                        : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradient-start/50'
                    } disabled:hover:border-border`}
                  >
                    {t.components.customSupplementsEditor.typePercent}
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      updateRule(rule.id, { mode: 'rate', rate: undefined, percent: undefined })
                    }
                    disabled={readOnly || !hasToTime}
                    className={`flex-1 px-3 py-2 text-sm rounded border transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                      rule.mode === 'rate'
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
                    ? rule.mode === 'percent'
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
                    value={rule.mode === 'percent' ? (rule.percent ?? '') : (rule.rate ?? '')}
                    onChange={(e) => {
                      const inputValue = e.target.value;
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
                      {rule.mode === 'percent' ? t.components.customSupplementsEditor.percentUnit : t.components.customSupplementsEditor.fixedUnit}
                    </span>
                  )}
                </div>
              </div>
            </Card>
          );
        })}

        {readOnly && rules.length === 0 && (
          <p className="text-sm text-text-secondary italic">
            {t.components.customSupplementsEditor.noSupplements}
          </p>
        )}

        {!readOnly && (
          <Button
            variant="outline"
            onClick={addRule}
            disabled={rules.some(
              (r) =>
                !r.from ||
                !r.to ||
                !r.mode ||
                ((r.mode === 'percent' && (r.percent === undefined || r.percent === 0)) ||
                 (r.mode === 'rate' && (r.rate === undefined || r.rate === 0)))
            )}
            className="w-full rounded-3xl"
          >
            <Plus className="h-4 w-4 mr-2" />
            {rules.length === 1 ? t.components.customSupplementsEditor.addOne : t.components.customSupplementsEditor.addMultiple}
          </Button>
        )}
      </div>
    </div>
  );
}
