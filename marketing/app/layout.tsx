import type { Metadata } from "next"
import { Inter } from "next/font/google"
import "./globals.css"

const inter = Inter({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700", "800"],
  variable: "--font-inter",
})

export const metadata: Metadata = {
  title: "Lønnskalkulator for Norge – riktig lønn hver måned | kkarlsen.dev",
  description: "Beregn lønn, overtid, tillegg og pauser på sekunder. Gratis å starte. Ingen Excel. Riktig fasit hver måned.",
  metadataBase: new URL("https://www.kkarlsen.dev"),
  openGraph: {
    type: "website",
    title: "Lønnskalkulator for Norge – riktig lønn hver måned",
    description: "Beregn lønn, overtid, tillegg og pauser på sekunder. Gratis å starte. Ingen Excel. Riktig fasit hver måned.",
    url: "https://www.kkarlsen.dev/",
    images: [
      {
        url: "https://www.kkarlsen.dev/og/landing.png",
        width: 1200,
        height: 630,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Lønnskalkulator for Norge – riktig lønn hver måned",
    description: "Beregn lønn, overtid, tillegg og pauser på sekunder. Gratis å starte. Ingen Excel. Riktig fasit hver måned.",
    images: ["https://www.kkarlsen.dev/og/landing.png"],
  },
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
      { url: "/favicon-48x48.png", sizes: "48x48", type: "image/png" },
      { url: "/favicon-192x192.png", sizes: "192x192", type: "image/png" },
    ],
    apple: [
      { url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" },
    ],
  },
  robots: {
    index: true,
    follow: true,
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="nb-NO">
      <head>
        <link rel="canonical" href="https://www.kkarlsen.dev/" />
        <link rel="alternate" hrefLang="nb-NO" href="https://www.kkarlsen.dev/" />
        <meta name="theme-color" content="#111111" />
      </head>
      <body className={`${inter.variable} font-sans antialiased`}>
        {children}
      </body>
    </html>
  )
}
