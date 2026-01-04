// components/app/Textarea.tsx
import * as React from "react";
import { Textarea as BaseTextarea } from "@ui/textarea";
import { cn } from "@/lib/cn";

type Props = React.ComponentProps<typeof BaseTextarea> & { invalid?: boolean };

export const Textarea = React.forwardRef<HTMLTextAreaElement, Props>(
  ({ className, invalid, ...props }, ref) => {
    return (
      <BaseTextarea
        {...props}
        ref={ref}
        aria-invalid={invalid || undefined}
        className={cn(invalid && "ring-1 ring-error", className)}
      />
    );
  }
);

Textarea.displayName = "Textarea";
