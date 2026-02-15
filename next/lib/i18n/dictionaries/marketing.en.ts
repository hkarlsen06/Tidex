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
        question: 'How are breaks handled?',
        answers: [
          'We calculate your salary intelligently. If you work more than 5.5 hours we automatically deduct a 30-minute break, just like most employers do.',
          'Working nights or long shifts? No problem. The calculator handles everything from regular days to overnight work. You can change the break rules in settings if your workplace uses something else.',
        ],
      },
      {
        question: 'How do overtime and supplements work?',
        answers: [
          'Tell us which supplements you are entitled to and we handle the rest automatically. Evening supplement from 18:00? Weekend supplement? Configure the rules once.',
          'When you log a shift the calculator looks at the day and time, then adds the correct supplements on top of your base pay. Easy.',
        ],
      },
      {
        question: 'Where is my data stored?',
        answers: [
          'Safe and sound. All of your settings live in our Supabase database.',
          'When you sign in we sync your shifts and settings to the cloud so you can move between phone and desktop without losing anything.',
        ],
      },
      {
        question: 'Can I download salary reports?',
        answers: [
          'Absolutely. Export every shift as a PDF or Excel (CSV) whenever you need it — perfect for submitting timesheets or staying on top of the month.',
          'The report includes all details: hours worked, breaks, supplements and total pay per shift.',
        ],
      },
      {
        question: 'What does it cost? Is it free?',
        answers: [
          'Yes, getting started is completely free. You can use the calculator as much as you like, but you can only keep shifts for one month at a time — which is enough for most people.',
          'Need more? Our Pro plan unlocks unlimited months for just NOK 29 per month — less than a cup of coffee each week.',
        ],
      },
      {
        question: 'Can I use it like an app on my phone?',
        answers: [
          'Yes. Install it as an app by opening the site in Safari or Chrome and choosing “Add to Home Screen”.',
          'It behaves like a regular app with its own icon. You need internet to sync, but most features keep working even if the connection is slow.',
        ],
      },
      {
        question: 'Is my data safe?',
        answers: [
          'Absolutely. We take privacy seriously. Your data (shifts and hourly rates) is only sent to the server when you choose to sign in — never otherwise.',
          'We only store what the calculator needs to function: your shifts, settings and profile photo. Nothing more.',
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
