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
    cleartext: false,
    errorPath: 'offline.html'
  },
  ios: {
    // Set WebView background to match splash screen
    backgroundColor: '#020817'
  }
};

export default config;