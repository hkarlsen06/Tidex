import baseConfig from '../tailwind.config.js';

const {
  content = [],
  presets,
  theme = {},
  plugins = [],
  ...rest
} = baseConfig;

const marketingContent = [
  './app/**/*.{ts,tsx}',
  './components/**/*.{ts,tsx}',
];

const mergedContent = Array.from(new Set([...content, ...marketingContent]));

const config = {
  ...rest,
  content: mergedContent,
  presets,
  theme: {
    ...theme,
    extend: {
      ...(theme?.extend ?? {}),
    },
  },
  plugins: [...plugins],
};

export default config;
