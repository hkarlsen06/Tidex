/** @type {import('tailwindcss').Config} */
import { createRequire } from 'module';
const require = createRequire(import.meta.url);

export default {
    darkMode: ["class"],
    content: [
    "./app/**/*.{js,ts,jsx,tsx}",
    "./components/**/*.{js,ts,jsx,tsx}"
  ],
  theme: {
  	extend: {
  		colors: {
  			background: {
  				DEFAULT: 'hsl(var(--background))',
  				secondary: 'hsl(var(--background-secondary))'
  			},
  			button: {
  				background: 'hsl(var(--button-background))'
  			},
  			surface: {
  				primary: 'hsl(var(--surface-primary))',
  				secondary: 'hsl(var(--surface-secondary))'
  			},
  			wage: {
  				current: 'hsl(var(--wage-current-bg))'
  			},
  			text: {
  				primary: 'hsl(var(--text-primary))',
  				secondary: 'hsl(var(--text-secondary))',
  				muted: 'hsl(var(--text-muted))',
  				inverse: 'hsl(var(--text-inverse))'
  			},
  			border: {
  				DEFAULT: 'hsl(var(--border))',
  				subtle: 'hsl(var(--border-subtle))'
  			},
  			brand: {
  				gradientStart: 'hsl(var(--brand-gradientStart))',
  				gradientMid: 'hsl(var(--brand-gradientMid))',
  				gradientEnd: 'hsl(var(--brand-gradientEnd))',
  				highlight: 'hsl(var(--brand-highlight))'
  			},
  			success: {
  				DEFAULT: 'hsl(var(--success))',
  				foreground: 'hsl(var(--success-foreground))',
  				subtle: 'hsl(var(--success-subtle))'
  			},
  			warning: {
  				DEFAULT: 'hsl(var(--warning))',
  				foreground: 'hsl(var(--warning-foreground))',
  				subtle: 'hsl(var(--warning-subtle))'
  			},
  			error: {
  				DEFAULT: 'hsl(var(--error))',
  				foreground: 'hsl(var(--error-foreground))',
  				subtle: 'hsl(var(--error-subtle))'
  			},
  			info: {
  				DEFAULT: 'hsl(var(--info))',
  				foreground: 'hsl(var(--info-foreground))',
  				subtle: 'hsl(var(--info-subtle))'
  			},
  			foreground: 'hsl(var(--foreground))',
  			card: {
  				DEFAULT: 'hsl(var(--card))',
  				foreground: 'hsl(var(--card-foreground))'
  			},
  			popover: {
  				DEFAULT: 'hsl(var(--popover))',
  				foreground: 'hsl(var(--popover-foreground))'
  			},
  			primary: {
  				DEFAULT: 'hsl(var(--primary))',
  				foreground: 'hsl(var(--primary-foreground))'
  			},
  			secondary: {
  				DEFAULT: 'hsl(var(--secondary))',
  				foreground: 'hsl(var(--secondary-foreground))'
  			},
  			muted: {
  				DEFAULT: 'hsl(var(--muted))',
  				foreground: 'hsl(var(--muted-foreground))'
  			},
  			accent: {
  				DEFAULT: 'hsl(var(--accent))',
  				foreground: 'hsl(var(--accent-foreground))'
  			},
  			destructive: {
  				DEFAULT: 'hsl(var(--destructive))',
  				foreground: 'hsl(var(--destructive-foreground))'
  			},
  			input: 'hsl(var(--input))',
  			ring: 'hsl(var(--ring))',
  			chart: {
  				'1': 'hsl(var(--chart-1))',
  				'2': 'hsl(var(--chart-2))',
  				'3': 'hsl(var(--chart-3))',
  				'4': 'hsl(var(--chart-4))',
  				'5': 'hsl(var(--chart-5))'
  			}
  		},
  		borderRadius: {
  			lg: 'var(--radius)',
  			md: 'calc(var(--radius) - 2px)',
  			sm: 'calc(var(--radius) - 4px)',
  			xl: 'calc(var(--radius) * 1.5)',
  			'2xl': 'calc(var(--radius) * 2)',
  			'3xl': 'calc(var(--radius) * 3)',
  			card: '1.75rem'
  		},
  		boxShadow: {
  			'app': '0 10px 40px -10px hsl(var(--shadow-color))',
  			'app-lg': '0 20px 60px -15px hsl(var(--shadow-color-strong))',
  			'app-inner': 'inset 0 2px 4px 0 hsl(var(--shadow-color))',
  			'app-sm': '0 1px 2px 0 rgba(0, 0, 0, 0.05)',
  			'app-md': '0 4px 6px -1px hsl(var(--shadow-color)), 0 2px 4px -2px hsl(var(--shadow-color))'
  		},
  		fontFamily: {
  			sans: [
  				'Inter',
  				'ui-sans-serif',
  				'system-ui',
  				'-apple-system',
  				'BlinkMacSystemFont',
  				'Segoe UI',
  				'sans-serif'
  			]
  		}
  	}
  },
  plugins: [require("tailwindcss-animate")]
};
