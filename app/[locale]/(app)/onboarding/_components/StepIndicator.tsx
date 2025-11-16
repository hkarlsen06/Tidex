import { Progress } from "@/components/app/Progress";

interface StepIndicatorProps {
  currentStep: number;
  totalSteps: number;
}

export function StepIndicator({ currentStep, totalSteps }: StepIndicatorProps) {
  const progress = (currentStep / totalSteps) * 100;

  return (
    <div className="space-y-2 mb-8">
      <div className="flex items-center justify-between text-sm">
        <span className="text-text-secondary">Steg {currentStep} av {totalSteps}</span>
        <span className="text-text-secondary">{Math.round(progress)}%</span>
      </div>
      <Progress value={progress} />
    </div>
  );
}
