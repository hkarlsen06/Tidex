"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { Card } from "@appui/Card";
import { StepIndicator } from "./StepIndicator";
import { WageStep } from "./WageStep";
import { BreakStep } from "./BreakStep";
import { PreferencesStep } from "./PreferencesStep";
import { CompletionStep } from "./CompletionStep";
import { completeOnboarding } from "../actions";
import { PRESET_WAGE_RATES } from "@/lib/payroll/calc";

interface OnboardingFormProps {
  initialSettings?: {
    use_preset?: boolean;
    current_wage_level?: number;
    custom_wage?: number;
    break_enabled?: boolean;
    break_method?: string;
    break_threshold_hours?: number;
    break_deduction_minutes?: number;
    theme?: string;
    default_shifts_view?: string;
    monthly_goal?: number;
  };
}

export function OnboardingForm({ initialSettings }: OnboardingFormProps) {
  const router = useRouter();
  const [currentStep, setCurrentStep] = useState(1);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Step 1: Wage
  const [wageType, setWageType] = useState<"preset" | "custom">(
    initialSettings?.use_preset !== false ? "preset" : "custom"
  );
  const [wageLevel, setWageLevel] = useState(
    initialSettings?.current_wage_level?.toString() || "1"
  );
  const [customWage, setCustomWage] = useState(
    initialSettings?.custom_wage?.toString() || "200"
  );

  // Step 2: Break
  const [breakEnabled, setBreakEnabled] = useState(
    initialSettings?.break_enabled !== false
  );
  const [threshold, setThreshold] = useState(
    initialSettings?.break_threshold_hours?.toString() || "5.5"
  );
  const [duration, setDuration] = useState(
    initialSettings?.break_deduction_minutes?.toString() || "30"
  );
  const [method, setMethod] = useState(
    initialSettings?.break_method || "proportional"
  );

  // Step 3: Preferences
  const [theme, setTheme] = useState(initialSettings?.theme || "dark");
  const [shiftsView, setShiftsView] = useState(
    initialSettings?.default_shifts_view || "list"
  );
  const [monthlyGoal, setMonthlyGoal] = useState(
    initialSettings?.monthly_goal?.toString() || "20000"
  );

  // Apply theme changes immediately
  useEffect(() => {
    const root = document.documentElement;
    if (theme === "system") {
      const systemTheme = window.matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark"
        : "light";
      root.classList.toggle("dark", systemTheme === "dark");
    } else {
      root.classList.toggle("dark", theme === "dark");
    }
  }, [theme]);

  const handleComplete = async () => {
    setIsSubmitting(true);
    try {
      const settings = {
        use_preset: wageType === "preset",
        current_wage_level: wageType === "preset" ? parseInt(wageLevel) : null,
        custom_wage: wageType === "custom" ? parseFloat(customWage) : null,
        break_enabled: breakEnabled,
        break_method: breakEnabled ? method : null,
        break_threshold_hours: breakEnabled ? parseFloat(threshold) : null,
        break_deduction_minutes: breakEnabled ? parseInt(duration) : null,
        theme,
        default_shifts_view: shiftsView,
        monthly_goal: monthlyGoal ? parseFloat(monthlyGoal) : null,
      };

      await completeOnboarding(settings);
      router.push("/");
      router.refresh();
    } catch (error) {
      console.error("Failed to complete onboarding:", error);
      setIsSubmitting(false);
    }
  };

  const getWageDisplay = () => {
    if (wageType === "preset") {
      const rate = PRESET_WAGE_RATES[parseInt(wageLevel) as keyof typeof PRESET_WAGE_RATES];
      return `${rate?.toFixed(2) || "0"} kr/t (Tariff Nivå ${wageLevel})`;
    }
    return `${customWage} kr/t`;
  };

  const totalSteps = 4;

  return (
    <div className="fixed inset-0 flex items-center justify-center p-4 bg-background">
      <Card className="w-full max-w-2xl p-8 shadow-app-lg backdrop-blur border-border bg-surface-secondary">
        {currentStep < totalSteps && (
          <StepIndicator currentStep={currentStep} totalSteps={totalSteps} />
        )}

        {currentStep === 1 && (
          <WageStep
            wageType={wageType}
            setWageType={setWageType}
            wageLevel={wageLevel}
            setWageLevel={setWageLevel}
            customWage={customWage}
            setCustomWage={setCustomWage}
            onNext={() => setCurrentStep(2)}
          />
        )}

        {currentStep === 2 && (
          <BreakStep
            breakEnabled={breakEnabled}
            setBreakEnabled={setBreakEnabled}
            threshold={threshold}
            setThreshold={setThreshold}
            duration={duration}
            setDuration={setDuration}
            method={method}
            setMethod={setMethod}
            onNext={() => setCurrentStep(3)}
            onBack={() => setCurrentStep(1)}
          />
        )}

        {currentStep === 3 && (
          <PreferencesStep
            theme={theme}
            setTheme={setTheme}
            shiftsView={shiftsView}
            setShiftsView={setShiftsView}
            monthlyGoal={monthlyGoal}
            setMonthlyGoal={setMonthlyGoal}
            onNext={() => setCurrentStep(4)}
            onBack={() => setCurrentStep(2)}
          />
        )}

        {currentStep === 4 && (
          <CompletionStep
            wageDisplay={getWageDisplay()}
            breakEnabled={breakEnabled}
            breakDuration={duration}
            breakThreshold={threshold}
            theme={theme}
            onComplete={handleComplete}
            isSubmitting={isSubmitting}
          />
        )}
      </Card>
    </div>
  );
}
