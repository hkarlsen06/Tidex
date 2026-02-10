export const AUTH_TOAST_EVENT = "tidex:auth-toast";

type AuthToastDetail = {
  message: string;
  durationMs?: number;
};

export function showAuthSuccessToast(message: string, durationMs = 2400) {
  if (!message || typeof window === "undefined") {
    return;
  }

  window.dispatchEvent(
    new CustomEvent<AuthToastDetail>(AUTH_TOAST_EVENT, {
      detail: { message, durationMs },
    })
  );
}

