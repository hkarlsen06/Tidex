const sharedConfig = require('../config/tailwind.config.js');

module.exports = {
  ...sharedConfig,
  content: [
    './app/**/*.{ts,tsx}',
    '../components/**/*.{ts,tsx}',
  ],
};
