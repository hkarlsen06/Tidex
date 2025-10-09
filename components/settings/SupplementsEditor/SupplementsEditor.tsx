'use client';

import { useState, useId } from 'react';
import { Label } from '@appui/Label';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Card } from '@appui/Card';
import { Badge } from '@appui/Badge';
import { Trash2, Plus } from 'lucide-react';
import { SupplementRule, SupplementsData } from './types';

interface SupplementsEditorProps {
  value: SupplementsData | null;
  onChange: (value: SupplementsData | null) => void;
  className?: string;
}

const DAY_LABELS = ['Man', 'Tir', 'Ons', 'Tor', 'Fre', 'Lør', 'Søn'];

export function SupplementsEditor({
  value,
  onChange,
  className,
}: SupplementsEditorProps) {
  const baseId = useId();

  // Initialize with one empty rule if no existing rules, or use existing rules
  const getInitialRules = (): SupplementRule[] => {
    if (value?.rules && value.rules.length > 0) {
      return value.rules.map((rule, index) => ({
        ...rule,
        id: `${index}`,
      }));
    }
    // Start with one empty rule so form is visible
    return [
      {
        id: '0',
        days: [],
        from: '',
        to: '',
        // No type pre-selected - user must choose percent or rate
      },
    ];
  };

  const [rules, setRules] = useState<SupplementRule[]>(getInitialRules());
  const [nextId, setNextId] = useState(() => rules.length);

  const addRule = () => {
    const newRule: SupplementRule = {
      id: `${nextId}`,
      days: [1, 2, 3, 4, 5],
      from: '18:00',
      to: '23:00',
      rate: 50, // Default to rate type (kr/t)
    };
    setRules([...rules, newRule]);
    setNextId(nextId + 1);
  };

  const removeRule = (id: string) => {
    const newRules = rules.filter((r) => r.id !== id);
    setRules(newRules);

    // Update parent immediately
    const validRules = newRules.filter(
      (rule) =>
        rule.days.length > 0 &&
        rule.from &&
        rule.to &&
        (rule.percent !== undefined || rule.rate !== undefined)
    );

    if (validRules.length > 0) {
      const cleanedRules = validRules.map(({ id, ...rest }) => rest) as any[];
      onChange({ rules: cleanedRules });
    } else {
      onChange(null);
    }
  };

  const updateRule = (id: string, updates: Partial<SupplementRule>) => {
    const newRules = rules.map((r) => (r.id === id ? { ...r, ...updates } : r));
    setRules(newRules);

    // Update parent immediately
    const validRules = newRules.filter(
      (rule) =>
        rule.days.length > 0 &&
        rule.from &&
        rule.to &&
        (rule.percent !== undefined || rule.rate !== undefined)
    );

    if (validRules.length > 0) {
      const cleanedRules = validRules.map(({ id, ...rest }) => rest) as any[];
      onChange({ rules: cleanedRules });
    } else {
      onChange(null);
    }
  };

  const toggleDay = (ruleId: string, day: number) => {
    const rule = rules.find((r) => r.id === ruleId);
    if (!rule) return;

    const days = rule.days.includes(day)
      ? rule.days.filter((d) => d !== day)
      : [...rule.days, day].sort();

    updateRule(ruleId, { days });
  };

  return (
    <div className={className}>
      <div className="space-y-4">
        {rules.map((rule) => {
          // Progressive enablement logic
          const hasDays = rule.days.length > 0;
          const hasFromTime = rule.from.length > 0;
          const hasToTime = rule.to.length > 0;
          const hasType = rule.percent !== undefined || rule.rate !== undefined;

          return (
            <Card key={rule.id} className="p-4 space-y-4 bg-surface-primary">
              <div className="flex items-center justify-between">
                <Badge variant="secondary">
                  Tillegg #{rules.indexOf(rule) + 1}
                </Badge>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => removeRule(rule.id)}
                  className="h-8 w-8 p-0"
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>

              {/* Days selector - always enabled */}
              <div className="space-y-2">
                <Label className="text-sm">Hvilke dager?</Label>
                <div className="grid grid-cols-4 gap-2">
                  {DAY_LABELS.map((label, idx) => {
                    const dayNum = idx + 1;
                    const isSelected = rule.days.includes(dayNum);
                    return (
                      <button
                        key={dayNum}
                        onClick={() => toggleDay(rule.id, dayNum)}
                        className={`px-2 py-1.5 text-xs sm:text-sm rounded border transition-colors ${
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
                className={`grid grid-cols-2 gap-3 transition-opacity ${
                  !hasDays ? 'opacity-40' : 'opacity-100'
                }`}
              >
                <div className="space-y-2">
                  <Label htmlFor={`${baseId}-from-${rule.id}`} className="text-sm">
                    Fra
                  </Label>
                  <Input
                    id={`${baseId}-from-${rule.id}`}
                    type="time"
                    value={rule.from}
                    onChange={(e) =>
                      updateRule(rule.id, { from: e.target.value })
                    }
                    disabled={!hasDays}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor={`${baseId}-to-${rule.id}`} className="text-sm">
                    Til
                  </Label>
                  <Input
                    id={`${baseId}-to-${rule.id}`}
                    type="time"
                    value={rule.to}
                    onChange={(e) =>
                      updateRule(rule.id, { to: e.target.value })
                    }
                    disabled={!hasDays || !hasFromTime}
                  />
                </div>
              </div>

              {/* Rate or Percent - disabled until times selected */}
              <div
                className={`space-y-2 transition-opacity ${
                  !hasToTime ? 'opacity-40' : 'opacity-100'
                }`}
              >
                <Label className="text-sm">Tilleggstype</Label>
                <div className="flex gap-2">
                  <button
                    onClick={() =>
                      updateRule(rule.id, { percent: 50, rate: undefined })
                    }
                    disabled={!hasToTime}
                    className={`flex-1 px-3 py-2 text-sm rounded border transition-colors ${
                      rule.percent !== undefined
                        ? 'bg-brand-gradientStart text-white border-brand-gradientStart'
                        : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradientStart/50'
                    } disabled:cursor-not-allowed disabled:hover:border-border`}
                  >
                    Prosent
                  </button>
                  <button
                    onClick={() =>
                      updateRule(rule.id, { rate: 50, percent: undefined })
                    }
                    disabled={!hasToTime}
                    className={`flex-1 px-3 py-2 text-sm rounded border transition-colors ${
                      rule.rate !== undefined
                        ? 'bg-brand-gradientStart text-white border-brand-gradientStart'
                        : 'bg-surface-secondary border-border text-text-secondary hover:border-brand-gradientStart/50'
                    } disabled:cursor-not-allowed disabled:hover:border-border`}
                  >
                    Fast beløp
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
                    ? rule.percent !== undefined
                      ? 'Prosent %'
                      : 'Beløp (kr/t)'
                    : 'Verdi'}
                </Label>
                <div className="relative">
                  <Input
                    id={`${baseId}-value-${rule.id}`}
                    type="number"
                    min={0}
                    step="any"
                    value={rule.percent ?? rule.rate ?? ''}
                    onChange={(e) => {
                      const val = e.target.value === '' ? 0 : parseFloat(e.target.value);
                      if (rule.percent !== undefined) {
                        updateRule(rule.id, { percent: val });
                      } else {
                        updateRule(rule.id, { rate: val });
                      }
                    }}
                    disabled={!hasType}
                    className={hasType ? 'pr-12' : ''}
                  />
                  {hasType && (
                    <span className="absolute right-4 top-1/2 -translate-y-1/2 text-text-secondary text-sm">
                      {rule.percent !== undefined ? '%' : 'kr/t'}
                    </span>
                  )}
                </div>
              </div>
            </Card>
          );
        })}

        <Button
          variant="outline"
          onClick={addRule}
          disabled={rules.some(
            (r) =>
              r.days.length === 0 ||
              !r.from ||
              !r.to ||
              (r.percent === undefined && r.rate === undefined)
          )}
          className="w-full rounded-3xl"
        >
          <Plus className="h-4 w-4 mr-2" />
          {rules.length === 1 ? 'Legg til ett til' : 'Legg til flere'}
        </Button>
      </div>
    </div>
  );
}
