/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx}",
    "./components/**/*.{js,ts,jsx,tsx}"
  ],
  theme: {
    extend: {
      colors: {
        background: {
          primary: "hsl(229 84% 5%)",
          secondary: "hsl(222 47% 11%)",
          tertiary: "hsl(217 33% 17%)",
        },
        surface: {
          primary: "hsl(220 49% 8%)",
          secondary: "hsl(221 39% 11%)",
        },
        text: {
          primary: "hsl(210 40% 98%)",
          secondary: "hsl(214 32% 91%)",
          muted: "hsl(215 20% 65%)",
          inverse: "hsl(222 47% 11%)",
        },
        border: {
          subtle: "hsl(215 16% 47%)",
          strong: "hsl(215 19% 35%)",
        },
        brand: {
          gradientStart: "hsl(199 89% 48%)",
          gradientMid: "hsl(189 94% 43%)",
          gradientEnd: "hsl(192 91% 36%)",
          highlight: "hsl(188 86% 53%)",
        }
      }
    }
  },
  plugins: []
};
