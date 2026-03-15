export const marketingEn = {
  meta: {
    title: 'Tidex — Calculate your pay — for free!',
    description: 'Stay on top of salary, supplements and overtime with Tidex. A modern wage calculator that keeps you in control.',
    ogTitle: 'Tidex — Calculate your pay — for free!',
    ogDescription: 'Track your salary, plan shifts and handle supplements automatically with Tidex.',
    ogImageAlt: 'Tidex — Full control over your salary',
  },
  hero: {
    title: 'Stay in control of your salary',
    description: 'The wage calculator that treats shifts, supplements and tariffs seriously. Excel is history.',
    highlights: ['Accurate', 'Fast', 'Private', 'Reliable'],
    primaryCta: 'Open the app',
    appStoreCta: 'Download on the App Store',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex logo',
  },
  features: {
    eyebrow: 'Why Tidex?',
    heading: 'Built for people who want full control',
    description: 'Our core features are designed to make salary calculations simple, precise and trustworthy.',
    items: [
      {
        icon: 'shield',
        title: 'Protect yourself from underpayment',
        description: 'Know what you will earn before you accept an extra shift.',
      },
      {
        icon: 'zap',
        title: 'Automatic supplements',
        description: 'Every supplement is calculated automatically for each shift.',
      },
      {
        icon: 'clock',
        title: 'Smooth calculations',
        description: 'Handles breaks, split shifts and overnight work without hassle.',
      },
      {
        icon: 'layers',
        title: 'Reports on demand',
        description: 'Download complete PDF reports and keep the full overview month by month.',
      },
    ],
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Frequently asked questions',
    description: 'Everything you need to know about shifts, reports and how we handle your data.',
    items: [
      {
        question: 'What does it cost? Is it free?',
        answers: [
          'Yes, you can get started for free with core features.',
          'For advanced usage, Pro provides unlimited months for NOK 29 per month.',
        ],
      },
      {
        question: 'Is there a native iOS app?',
        answers: [
          'Yes. Tidex has a native iOS app built with SwiftUI, available from the App Store.',
          'The iOS app uses the same secure backend and account system as the rest of Tidex, so your shifts, settings and subscription stay in sync.',
        ],
      },
      {
        question: 'Is the web app still available?',
        answers: [
          'No. The old web app has been retired because too few people used it to justify maintaining it alongside the native app.',
          'Tidex is built by a solo developer, so I need to focus my time where it helps the most. Right now that means the iOS app, which is where the active user base is.',
          'If you have an old website account or billing question, contact support and we will help manually.',
        ],
      },
      {
        question: 'How are breaks handled?',
        answers: [
          'We calculate salary smartly: if you work more than 5.5 hours, a 30-minute break is deducted automatically, with the same defaults used by most employers.',
          'If your workplace uses different rules, you can override break behavior in settings, including shifts that cross midnight.',
        ],
      },
      {
        question: 'How do overtime and supplements work?',
        answers: [
          'Tell us which supplements you are entitled to and we handle the rest automatically. Evening supplement from 18:00? Weekend supplement? Configure the rules once.',
          'When you log a shift, the calculator checks the date and time and applies the right supplements on top of your base pay.',
        ],
      },
      {
        question: 'Can I download salary reports?',
        answers: [
          'Absolutely. Export every shift as PDF or Excel (CSV) any time, e.g. for payroll and timesheet reporting.',
          'Reports include working hours, breaks, supplements and total pay for each shift.',
        ],
      },
      {
        question: 'Where is my data stored?',
        answers: [
          'Your account data is stored in secure Supabase tables.',
          'The iOS app uses local-first storage and syncs with the shared backend, so your data stays available on your device while remaining backed up to your account.',
        ],
      },
      {
        question: 'Is my data safe?',
        answers: [
          'Absolutely. We take privacy seriously. Your shift data is only sent to the server when needed for sign-in and sync.',
          'We only persist what is required for app functionality: your shifts, settings and profile details.',
        ],
      },
    ],
  },
  ctaPrimary: {
    heading: 'Ready to try your shifts?',
    description: 'Create a free account and get control over supplements, overtime and reports before the next payday.',
    button: 'Get started — free',
  },
  contact: {
    heading: 'Have questions?',
    description: 'Reach out if anything is unclear or if you have feedback.',
    button: 'Contact us',
    emailSubject: 'Contact from Tidex',
    emailBody: 'Hi!\n\nI have a question about ...',
  },
  footer: {
    payrollDocs: 'Payroll Documentation',
    privacy: 'Privacy policy',
    terms: 'Terms of use',
    copyright: '© 2026 Hjalmar Kristensen-Karlsen',
  },
} as const;
