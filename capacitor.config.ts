import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'no.tidex.app',
  appName: 'Tidex',
  webDir: 'dist',
  server: {
    url: 'https://app.tidex.no',
    cleartext: false,
    errorPath: 'offline.html'
  }
};

export default config;