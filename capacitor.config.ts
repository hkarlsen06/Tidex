import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'no.tidex.app',
  appName: 'Tidex',
  webDir: 'dist',
  // Background color matching splash screen and dark theme (#020817)
  // Prevents white flash during WebView load
  backgroundColor: '#020817',
  server: {
    url: 'https://app.tidex.no',
    cleartext: false
    // errorPath removed - native iOS offline screen handles network errors
  },
  ios: {
    // Set WebView background to match splash screen
    backgroundColor: '#020817'
  },
  android: {
    // Set WebView background to match splash screen (prevents white flash)
    backgroundColor: '#020817',
    // Disable mixed content (HTTP on HTTPS pages)
    allowMixedContent: false,
    // Disable WebView debugging in production
    webContentsDebuggingEnabled: false
  }
};

export default config;