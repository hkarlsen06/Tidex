"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion } from "motion/react";
import { Card } from "@/components/app/Card";
import { TooltipProvider } from "@/components/app/Tooltip";
import { StepIndicator } from "./StepIndicator";
import { WageStep } from "./WageStep";
import { SupplementsStep } from "./SupplementsStep";
import { BreakStep } from "./BreakStep";
import { TaxPayrollStep } from "./TaxPayrollStep";
import { PreferencesStep } from "./PreferencesStep";
import { SecurityStep } from "./SecurityStep";
import { CompletionStep } from "./CompletionStep";
import { completeOnboarding } from "../actions";
import { supabase } from "@/lib/supabase/browser";
import { getLatestTariffVersionAction, getTariffTypesAction } from "@/app/[locale]/(app)/settings/pay/_actions/wage-snapshots";
import type { TariffVersion, TariffType } from "@/data-access/tariff";
import { SupplementsData } from "@/components/settings/SupplementsEditor";
import { ScrollablePageWrapper } from "@/components/app/ScrollablePageWrapper";
import { HideNativeTabBar } from "@/components/app/HideNativeTabBar";

// Animation variants for entrance animation
const cardVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

interface OnboardingFormProps {
  initialSettings?: {
    use_preset?: boolean;
    current_wage_level?: number;
    custom_wage?: number;
    custom_supplements?: any;
    pause_deduction_enabled?: boolean;
    pause_deduction_method?: string;
    pause_threshold_hours?: number;
    pause_deduction_minutes?: number;
    tax_deduction_enabled?: boolean;
    tax_percentage?: number;
    payroll_day?: number;
    theme?: string;
    default_shifts_view?: string;
    monthly_goal?: number;
    currency?: string;
  };
}

export function OnboardingForm({ initialSettings }: OnboardingFormProps) {
  const router = useRouter();
  const [currentStep, setCurrentStep] = useState(1);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Tariff types and version for displaying accurate rates
  const [tariffTypes, setTariffTypes] = useState<TariffType[]>([]);
  const [selectedTariffTypeId, setSelectedTariffTypeId] = useState<string>("hk_retail");
  const [tariffVersion, setTariffVersion] = useState<TariffVersion | null>(null);

  // Fetch tariff types and latest version on mount
  useEffect(() => {
    const loadTariffData = async () => {
      try {
        // Load tariff types
        const types = await getTariffTypesAction();
        setTariffTypes(types);

        // Set default tariff type
        const defaultType = types.find((t) => t.is_default) ?? types[0];
        if (defaultType) {
          setSelectedTariffTypeId(defaultType.id);
          // Load tariff version for default type
          const version = await getLatestTariffVersionAction(defaultType.id);
          setTariffVersion(version);
        }
      } catch (error) {
        console.warn("Failed to fetch tariff data:", error);
      }
    };

    loadTariffData();
  }, []);

  // Refetch tariff version when selected type changes
  useEffect(() => {
    if (selectedTariffTypeId) {
      getLatestTariffVersionAction(selectedTariffTypeId)
        .then(setTariffVersion)
        .catch((error) => {
          console.warn("Failed to fetch tariff version:", error);
        });
    }
  }, [selectedTariffTypeId]);

  // Step 1: Currency
  const [currency, setCurrency] = useState(
    initialSettings?.currency || "kr"
  );

  // Step 2: Wage (custom is now the default)
  const [wageType, setWageType] = useState<"preset" | "custom">(
    initialSettings?.use_preset === true ? "preset" : "custom"
  );
  const [wageLevel, setWageLevel] = useState(
    initialSettings?.current_wage_level?.toString() || "1"
  );
  const [customWage, setCustomWage] = useState(
    initialSettings?.custom_wage?.toString() || "200"
  );

  // Step 2: Custom Supplements
  const [customSupplements, setCustomSupplements] = useState<SupplementsData | null>(
    initialSettings?.custom_supplements || null
  );

  // Step 3: Break
  const initialBreakEnabled =
    initialSettings?.pause_deduction_enabled ??
    false;
  const initialThresholdValue =
    initialSettings?.pause_threshold_hours ??
    null;
  const initialDurationValue =
    initialSettings?.pause_deduction_minutes ??
    null;
  const initialBreakMethod =
    initialSettings?.pause_deduction_method ??
    "proportional";

  const [breakEnabled, setBreakEnabled] = useState(
    initialBreakEnabled
  );
  const [threshold, setThreshold] = useState(
    initialThresholdValue !== null ? initialThresholdValue.toString() : "5.5"
  );
  const [duration, setDuration] = useState(
    initialDurationValue !== null ? initialDurationValue.toString() : "30"
  );
  const [method, setMethod] = useState(
    initialBreakMethod
  );
  const [breakThresholdActivated, setBreakThresholdActivated] = useState(
    initialThresholdValue !== null
  );
  const [breakDurationActivated, setBreakDurationActivated] = useState(
    initialDurationValue !== null
  );
  const [breakMethodActivated, setBreakMethodActivated] = useState(
    Boolean(initialSettings?.pause_deduction_method)
  );

  // Step 4: Tax & Payroll
  const [taxDeductionEnabled, setTaxDeductionEnabled] = useState(
    initialSettings?.tax_deduction_enabled || false
  );
  const [taxPercentage, setTaxPercentage] = useState(
    initialSettings?.tax_percentage?.toString() || "30"
  );
  const [payrollDay, setPayrollDay] = useState(
    initialSettings?.payroll_day?.toString() || ""
  );

  // Step 5: Preferences
  const [theme, setTheme] = useState(initialSettings?.theme || "dark");
  const [shiftsView, setShiftsView] = useState(
    initialSettings?.default_shifts_view || "calendar"
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
      const parsedThreshold = breakEnabled ? Number.parseFloat(threshold) : null;
      const parsedDuration = breakEnabled ? Number.parseInt(duration, 10) : null;
      const breakMethod = breakEnabled ? method : null;

      const settings = {
        use_preset: wageType === "preset",
        current_wage_level: wageType === "preset" ? parseInt(wageLevel) : null,
        tariff_type_id: wageType === "preset" ? selectedTariffTypeId : null,
        custom_wage: wageType === "custom" ? parseFloat(customWage) : null,
        custom_supplements: customSupplements,
        pause_deduction_enabled: breakEnabled,
        pause_deduction_method: breakMethod,
        pause_threshold_hours: parsedThreshold,
        pause_deduction_minutes: parsedDuration,
        tax_deduction_enabled: taxDeductionEnabled,
        tax_percentage: taxDeductionEnabled && taxPercentage ? parseFloat(taxPercentage) : null,
        payroll_day: payrollDay ? parseInt(payrollDay) : null,
        theme,
        default_shifts_view: shiftsView,
        monthly_goal: monthlyGoal ? parseFloat(monthlyGoal) : null,
        currency,
      };

      await completeOnboarding(settings);
      // Refresh client-side session to get new JWT with updated finishedOnboarding flag.
      // This ensures the next page load has the correct session state.
      await supabase.auth.refreshSession();
      router.push("/shifts/add");
    } catch (error) {
      console.error("Failed to complete onboarding:", error);
      setIsSubmitting(false);
    }
  };

  const getWageDisplay = () => {
    if (wageType === "preset") {
      if (!tariffVersion) {
        return "Loading...";
      }
      const rate = tariffVersion.rates[wageLevel];
      return `${rate?.toFixed(2) || "0"} kr/t (Tariff Nivå ${wageLevel})`;
    }
    return `${customWage} kr/t`;
  };

  const totalSteps = 7;

  return (
    <ScrollablePageWrapper routeKey="onboarding" applyContainer={false}>
      <HideNativeTabBar />
      <TooltipProvider>
        <motion.div
          className="min-h-full flex justify-center pt-8 px-4 bg-background"
          variants={cardVariants}
          initial="hidden"
          animate="visible"
        >
        <Card className="w-full max-w-2xl h-fit p-8 shadow-app-lg backdrop-blur-sm border-border bg-surface-secondary">
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
            currency={currency}
            setCurrency={setCurrency}
            tariffTypes={tariffTypes}
            selectedTariffTypeId={selectedTariffTypeId}
            setSelectedTariffTypeId={setSelectedTariffTypeId}
            tariffVersion={tariffVersion}
            onNext={() => setCurrentStep(2)}
          />
        )}

        {currentStep === 2 && (
          <SupplementsStep
            customSupplements={customSupplements}
            setCustomSupplements={setCustomSupplements}
            wageType={wageType}
            onNext={() => setCurrentStep(3)}
            onBack={() => setCurrentStep(1)}
          />
        )}

        {currentStep === 3 && (
          <BreakStep
            breakEnabled={breakEnabled}
            setBreakEnabled={setBreakEnabled}
            threshold={threshold}
            setThreshold={setThreshold}
            duration={duration}
            setDuration={setDuration}
            method={method}
            setMethod={setMethod}
            thresholdActivated={breakThresholdActivated}
            setThresholdActivated={setBreakThresholdActivated}
            durationActivated={breakDurationActivated}
            setDurationActivated={setBreakDurationActivated}
            methodActivated={breakMethodActivated}
            setMethodActivated={setBreakMethodActivated}
            onNext={() => setCurrentStep(4)}
            onBack={() => setCurrentStep(2)}
          />
        )}

        {currentStep === 4 && (
          <TaxPayrollStep
            taxDeductionEnabled={taxDeductionEnabled}
            setTaxDeductionEnabled={setTaxDeductionEnabled}
            taxPercentage={taxPercentage}
            setTaxPercentage={setTaxPercentage}
            payrollDay={payrollDay}
            setPayrollDay={setPayrollDay}
            onNext={() => setCurrentStep(5)}
            onBack={() => setCurrentStep(3)}
          />
        )}

        {currentStep === 5 && (
          <PreferencesStep
            theme={theme}
            setTheme={setTheme}
            shiftsView={shiftsView}
            setShiftsView={setShiftsView}
            monthlyGoal={monthlyGoal}
            setMonthlyGoal={setMonthlyGoal}
            onNext={() => setCurrentStep(6)}
            onBack={() => setCurrentStep(4)}
          />
        )}

        {currentStep === 6 && (
          <SecurityStep
            onNext={() => setCurrentStep(7)}
            onBack={() => setCurrentStep(5)}
          />
        )}

        {currentStep === 7 && (
          <CompletionStep
            wageDisplay={getWageDisplay()}
            customSupplements={customSupplements}
            breakEnabled={breakEnabled}
            breakDuration={duration}
            breakThreshold={threshold}
            taxDeductionEnabled={taxDeductionEnabled}
            taxPercentage={taxPercentage}
            payrollDay={payrollDay}
            theme={theme}
            onComplete={handleComplete}
            isSubmitting={isSubmitting}
          />
        )}
        </Card>
        </motion.div>
      </TooltipProvider>
    </ScrollablePageWrapper>
  );
}
