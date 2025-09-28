// components/app/Button.tsx
import * as React from "react";
import { Button as BaseButton } from "@ui/button";
import { cn } from "@/lib/cn";

type Props = React.ComponentProps<typeof BaseButton> & {
  loading?: boolean;
};

export function Button({ className, loading, children, ...props }: Props) {
  return (
    <BaseButton
      {...props}
      disabled={loading || props.disabled}
      className={cn("font-medium", className)}
    >
      {loading ? "…" : children}
    </BaseButton>
  );
}
