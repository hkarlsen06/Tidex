import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface GroupedInputProps {
  children: ReactNode;
  className?: string;
}

/**
 * Groups multiple input fields in a single rounded container
 * with surface-primary background, matching the iOS grouped input style.
 *
 * Caller is responsible for placing `<GroupedInputDivider />` between inputs
 * and passing borderless className overrides to each input.
 */
export function GroupedInput({ children, className }: GroupedInputProps) {
  return (
    <div className={cn("bg-surface-primary rounded-xl overflow-hidden", className)}>
      {children}
    </div>
  );
}

/** Thin horizontal divider between grouped input fields */
export function GroupedInputDivider() {
  return <div className="h-px bg-border-subtle mx-4" />;
}

/** Class overrides to make Input/PasswordInput borderless inside a GroupedInput */
export const groupedInputClassName =
  "border-0 rounded-none shadow-none focus-visible:ring-0 bg-transparent h-11 px-4";
