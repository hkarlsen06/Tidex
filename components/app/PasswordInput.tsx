// components/app/PasswordInput.tsx
import * as React from "react";
import { Eye, EyeOff } from "lucide-react";
import { Input } from "@/components/app/Input";
import { cn } from "@/lib/cn";

type Props = Omit<React.ComponentProps<typeof Input>, "type"> & {
  invalid?: boolean;
};

export const PasswordInput = React.forwardRef<HTMLInputElement, Props>(
  ({ className, invalid, ...props }, ref) => {
    const [showPassword, setShowPassword] = React.useState(false);

    const togglePasswordVisibility = () => {
      setShowPassword((prev) => !prev);
    };

    return (
      <div className="relative">
        <Input
          {...props}
          ref={ref}
          type={showPassword ? "text" : "password"}
          invalid={invalid}
          className={cn("pr-10", className)}
        />
        <button
          type="button"
          onClick={togglePasswordVisibility}
          className="absolute right-0 top-0 h-full px-3 flex items-center text-text-muted hover:text-text-primary transition-colors"
          aria-label={showPassword ? "Hide password" : "Show password"}
          tabIndex={-1}
        >
          {showPassword ? (
            <EyeOff className="h-4 w-4" aria-hidden="true" />
          ) : (
            <Eye className="h-4 w-4" aria-hidden="true" />
          )}
        </button>
      </div>
    );
  }
);

PasswordInput.displayName = "PasswordInput";
