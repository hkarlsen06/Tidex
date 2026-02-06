function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

function decodeBase64(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

export async function shareDocument(
  pdfBase64: string,
  filename: string
): Promise<void> {
  const blob = new Blob([decodeBase64(pdfBase64)], {
    type: "application/pdf",
  });
  downloadBlob(blob, filename);
}

export async function shareCsvDocument(
  csvContent: string,
  filename: string
): Promise<void> {
  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  downloadBlob(blob, filename);
}
