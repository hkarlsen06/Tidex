"use client";

import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";

interface AddShiftFormContextValue {
  /**
   * Whether the form can be submitted (has valid data).
   */
  canSubmit: boolean;

  /**
   * Whether the form is currently submitting.
   */
  isSubmitting: boolean;

  /**
   * Register the form's submit function and state.
   * Called by AddShiftForm to expose its submit capability.
   */
  registerForm: (config: {
    submit: () => void;
    canSubmit: boolean;
    isSubmitting: boolean;
  }) => void;

  /**
   * Unregister the form (called on unmount).
   */
  unregisterForm: () => void;

  /**
   * Trigger form submission from external components (e.g., NavBar).
   */
  submitForm: () => void;

  /**
   * Whether a form is currently registered.
   */
  isFormRegistered: boolean;
}

const AddShiftFormContext = createContext<AddShiftFormContextValue | null>(null);

interface AddShiftFormProviderProps {
  children: ReactNode;
}

export function AddShiftFormProvider({ children }: AddShiftFormProviderProps) {
  const [formState, setFormState] = useState<{
    submit: (() => void) | null;
    canSubmit: boolean;
    isSubmitting: boolean;
  }>({
    submit: null,
    canSubmit: false,
    isSubmitting: false,
  });

  const registerForm = useCallback(
    (config: { submit: () => void; canSubmit: boolean; isSubmitting: boolean }) => {
      setFormState({
        submit: config.submit,
        canSubmit: config.canSubmit,
        isSubmitting: config.isSubmitting,
      });
    },
    []
  );

  const unregisterForm = useCallback(() => {
    setFormState({
      submit: null,
      canSubmit: false,
      isSubmitting: false,
    });
  }, []);

  const submitForm = useCallback(() => {
    if (formState.submit && formState.canSubmit && !formState.isSubmitting) {
      formState.submit();
    }
  }, [formState]);

  return (
    <AddShiftFormContext.Provider
      value={{
        canSubmit: formState.canSubmit,
        isSubmitting: formState.isSubmitting,
        registerForm,
        unregisterForm,
        submitForm,
        isFormRegistered: formState.submit !== null,
      }}
    >
      {children}
    </AddShiftFormContext.Provider>
  );
}

export function useAddShiftForm() {
  const context = useContext(AddShiftFormContext);
  if (!context) {
    throw new Error("useAddShiftForm must be used within an AddShiftFormProvider");
  }
  return context;
}

/**
 * Safe version that returns null if not within provider.
 * Use this in components that may render outside the provider.
 */
export function useAddShiftFormSafe() {
  return useContext(AddShiftFormContext);
}
