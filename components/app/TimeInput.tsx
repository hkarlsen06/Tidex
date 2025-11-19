// components/app/TimeInput.tsx
"use client";

import * as React from "react";
import { Input } from "@/components/app/Input";
import { cn } from "@/lib/cn";

type TimeInputProps = {
  id?: string;
  value: string;
  onChange: (value: string) => void;
  className?: string;
  onComplete?: () => void; // Called when user finishes entering time
  onEnter?: () => void; // Called when user presses Enter key
  step?: number;
  disabled?: boolean;
};

export const TimeInput = React.forwardRef<HTMLInputElement, TimeInputProps>(
  ({ id, value, onChange, className, onComplete, onEnter, step: _step = 900, disabled }, ref) => {
    const [inputValue, setInputValue] = React.useState(value);
    const internalRef = React.useRef<HTMLInputElement>(null);
    const inputRef = (ref as React.RefObject<HTMLInputElement | null>) || internalRef;

    React.useEffect(() => {
      setInputValue(value);
    }, [value]);

    const formatTimeInput = (input: string): string => {
      // Remove all non-digit characters
      const digits = input.replace(/\D/g, "");

      if (digits.length === 0) return "";
      if (digits.length <= 2) return digits;

      // Format as HH:MM
      const hours = digits.substring(0, 2);
      const minutes = digits.substring(2, 4);
      return `${hours}:${minutes}`;
    };

    const isValidTime = (time: string): boolean => {
      if (!/^\d{2}:\d{2}$/.test(time)) return false;
      const [h, m] = time.split(":").map(Number);
      return h >= 0 && h <= 23 && m >= 0 && m <= 59;
    };

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = e.target.value;
      const digits = newValue.replace(/\D/g, "");

      // Limit to 4 digits (HHMM)
      if (digits.length > 4) return;

      let formatted = formatTimeInput(digits);
      setInputValue(formatted);

      // Only update parent with valid complete times
      if (isValidTime(formatted)) {
        onChange(formatted);

        // If we have a complete time (4 digits entered), call onComplete
        if (digits.length === 4 && onComplete) {
          setTimeout(() => {
            onComplete();
          }, 0);
        }
      } else if (formatted === "") {
        onChange("");
      }
    };

    const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
      // Handle Enter key - call onEnter callback if provided
      if (e.key === 'Enter' && onEnter) {
        e.preventDefault();
        onEnter();
        return;
      }

      // Allow: backspace, delete, tab, escape, enter, arrow keys
      if ([
        'Backspace', 'Delete', 'Tab', 'Escape', 'Enter',
        'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'
      ].includes(e.key)) {
        return;
      }

      // Allow Ctrl/Cmd combinations
      if (e.ctrlKey || e.metaKey) {
        return;
      }

      // Only allow numbers
      if (!/^\d$/.test(e.key)) {
        e.preventDefault();
        return;
      }

      const input = inputRef.current;
      if (!input) return;

      const digits = inputValue.replace(/\D/g, "");

      // Auto-complete logic for smart input
      if (digits.length === 1) {
        const firstDigit = parseInt(digits);
        const newDigit = parseInt(e.key);

        // If first digit is 3-9, auto-prefix with 0 and add colon
        if (firstDigit >= 3) {
          e.preventDefault();
          const formatted = `0${firstDigit}:${newDigit}`;
          setInputValue(formatted);
          if (isValidTime(formatted)) {
            onChange(formatted);
          }
          return;
        }
      } else if (digits.length === 2) {
        // After two hour digits, add colon automatically
        const hours = parseInt(digits);
        if (hours > 23) {
          e.preventDefault();
          return;
        }
      } else if (digits.length === 3) {
        const minuteFirst = parseInt(digits[2]);

        // If minute first digit is 6-9, auto-prefix with 0
        if (minuteFirst >= 6) {
          e.preventDefault();
          const hours = digits.substring(0, 2);
          const formatted = `${hours}:0${minuteFirst}`;
          setInputValue(formatted);
          if (isValidTime(formatted)) {
            onChange(formatted);
          }
          setTimeout(() => {
            if (onComplete) {
              onComplete();
            }
          }, 0);
          return;
        }
      }
    };

    const handleBlur = () => {
      // On blur, validate and format the time
      if (inputValue && isValidTime(inputValue)) {
        onChange(inputValue);
        return;
      }

      // Auto-complete partial times
      if (inputValue) {
        const digits = inputValue.replace(/\D/g, "");

        if (digits.length === 1 || digits.length === 2) {
          // User entered only hour(s), assume ":00" for minutes
          const hours = digits.padStart(2, "0");
          const formatted = `${hours}:00`;
          if (isValidTime(formatted)) {
            setInputValue(formatted);
            onChange(formatted);
            return;
          }
        } else if (digits.length === 3) {
          // User entered HHM, assume second minute digit is 0
          const hours = digits.substring(0, 2);
          const minute = digits.substring(2, 3);
          const formatted = `${hours}:${minute}0`;
          if (isValidTime(formatted)) {
            setInputValue(formatted);
            onChange(formatted);
            return;
          }
        }

        // If still invalid, revert to the last valid value
        setInputValue(value);
      }
    };

    return (
      <Input
        id={id}
        ref={inputRef}
        type="text"
        inputMode="numeric"
        placeholder="HH:MM"
        value={inputValue}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        maxLength={5}
        disabled={disabled}
        className={cn("h-10 flex-1 rounded-xl border-border-subtle bg-transparent text-base text-text-primary", className)}
      />
    );
  }
);

TimeInput.displayName = "TimeInput";
