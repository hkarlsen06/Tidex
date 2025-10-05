// components/app/Input.tsx
import * as React from "react";
import { Input as BaseInput } from "@ui/input";
import { cn } from "@/lib/cn";

type Props = React.ComponentProps<typeof BaseInput> & { invalid?: boolean };

export function Input({ className, invalid, ...props }: Props) {
  return (
    <BaseInput
      {...props}
      aria-invalid={invalid || undefined}
      className={cn(invalid && "ring-1 ring-error", className)}
    />
  );
}
