import { registerPlugin, Capacitor } from "@capacitor/core";

/**
 * Custom DocumentShare plugin interface for native iOS document sharing.
 * This plugin handles file writing and sharing in a single call, avoiding
 * the complexity of separate Filesystem + Share plugins.
 */
interface DocumentSharePlugin {
  shareDocument(options: {
    data: string;
    filename: string;
    mimeType: string;
  }): Promise<void>;
}

// Register the custom plugin (only used on native)
const DocumentShare = registerPlugin<DocumentSharePlugin>("DocumentShare");

/**
 * Check if we should use native sharing.
 * Uses multiple detection methods to ensure we catch native iOS.
 */
function shouldUseNativeShare(): boolean {
  if (typeof window === "undefined") return false;

  // Check Capacitor bridge - most reliable method
  try {
    if (Capacitor.isNativePlatform() && Capacitor.getPlatform() === "ios") {
      return true;
    }
  } catch {
    // Capacitor not available, try fallbacks
  }

  // Fallback: Check for native-ios CSS class (set by inline script in layout.tsx)
  if (document.documentElement.classList.contains("native-ios")) {
    return true;
  }

  return false;
}

/**
 * Convert string to base64.
 */
function stringToBase64(str: string): string {
  // Use TextEncoder for proper UTF-8 encoding
  const encoder = new TextEncoder();
  const bytes = encoder.encode(str);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Save and share a PDF document on native iOS/Android.
 * On web, falls back to standard browser download.
 *
 * @param pdfBase64 - Base64-encoded PDF data (without data URI prefix)
 * @param filename - The filename to use when saving/sharing
 * @returns Promise that resolves when sharing is complete
 */
export async function shareDocument(
  pdfBase64: string,
  filename: string
): Promise<void> {
  if (!shouldUseNativeShare()) {
    // Web fallback - create a blob and download
    const byteCharacters = atob(pdfBase64);
    const byteNumbers = new Array(byteCharacters.length);
    for (let i = 0; i < byteCharacters.length; i++) {
      byteNumbers[i] = byteCharacters.charCodeAt(i);
    }
    const byteArray = new Uint8Array(byteNumbers);
    const blob = new Blob([byteArray], { type: "application/pdf" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    return;
  }

  // Native - use custom DocumentShare plugin
  await DocumentShare.shareDocument({
    data: pdfBase64,
    filename,
    mimeType: "application/pdf",
  });
}

/**
 * Save and share a CSV document on native iOS/Android.
 * On web, falls back to standard browser download.
 *
 * @param csvContent - CSV content as string
 * @param filename - The filename to use when saving/sharing
 * @returns Promise that resolves when sharing is complete
 */
export async function shareCsvDocument(
  csvContent: string,
  filename: string
): Promise<void> {
  if (!shouldUseNativeShare()) {
    // Web fallback - create a blob and download
    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    return;
  }

  // Native - convert to base64 and use custom DocumentShare plugin
  const base64Data = stringToBase64(csvContent);
  await DocumentShare.shareDocument({
    data: base64Data,
    filename,
    mimeType: "text/csv",
  });
}
