export const marketingEn = {
  meta: {
    title: 'Pay Calculator | Tidex',
    description: 'Stay on top of salary, supplements and overtime with Tidex. A modern wage calculator that keeps you in control.',
    ogTitle: 'Tidex | Hourly Pay',
    ogDescription: 'Track your salary, plan shifts and handle supplements automatically with Tidex.',
    ogImageAlt: 'Tidex — Full control over your salary',
  },
  hero: {
    eyebrow: 'iPhone app',
    title: 'Know what your shift is worth',
    description: '...so you always know what you will actually get paid.',
    primaryCta: 'See next paycheck',
    appStoreCta: 'See next paycheck',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex logo',
    screenshotAlt: 'Screenshot of the Tidex iPhone app showing the dashboard and shifts overview.',
    trustNote: 'Free to start. Built for real shift work.',
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Frequently asked questions',
    description: 'Everything you need to know about shifts, reports and how we handle your data.',
    items: [
      {
        question: 'What is Tidex, and why should I use it?',
        answers: [
          'Tidex is an iPhone app for shift workers who want to know what each shift is actually worth before payday.',
          'It gives you a clear estimate of salary, supplements, overtime and breaks in one place, so you can plan better, catch mistakes and feel more in control of your income.',
        ],
      },
      {
        question: 'How much does Tidex cost?',
        answers: [
          'You can get started for free with the core features.',
          'If you want more, Pro costs NOK 29 per month and includes unlimited history.',
        ],
      },
      {
        question: 'How do I set up shifts and get accurate pay?',
        answers: [
          'Add your base hourly rate, relevant supplements and break preference once in settings.',
          'After that, enter a new shift and Tidex calculates the payout with the same rules every time, so numbers stay consistent.',
        ],
      },
      {
        question: 'How are breaks, overtime, and extra pay handled?',
        answers: [
          'The app applies your configured rules for overtime, supplements, and breaks before showing totals.',
          'Most users can rely on defaults for a first setup, then tune details if their employer has specific contracts.',
        ],
      },
      {
        question: 'Can I export a pay report from my app?',
        answers: [
          'Yes. You can export all shifts as PDF or CSV from the app whenever you need a clean record.',
          'Those reports are easy to share with your workplace or use for your own bookkeeping.',
        ],
      },
      {
        question: 'Where is my data stored?',
        answers: [
          'Your data is stored securely and tied to your account.',
          'The app syncs your data so it stays available on your device and follows you when you sign in.',
        ],
      },
      {
        question: 'Is my data safe?',
        answers: [
          'Yes. We take privacy seriously, and your shift data is only sent when needed for sign-in and sync.',
          'We only store what the app needs to work: your shifts, settings and profile details.',
        ],
      },
    ],
  },
  socialProof: {
    eyebrow: 'Built for real shifts',
    heading: 'Why people keep using it',
    description: 'People use Tidex for predictable pay planning, clearer overtime calculations, and fast follow-up reports.',
    items: [
      {
        title: 'Clear math',
        description: 'Every line in the total is visible, so you can understand exactly what changed in your pay.',
      },
      {
        title: 'Report-ready exports',
        description: 'Export clean reports quickly when you want to check payroll or share shift details.',
      },
      {
        title: 'Fast to start',
        description: 'Set up your rules once and get useful estimates for each shift without complex steps.',
      },
    ],
  },
  ctaPrimary: {
    heading: 'Ready to try with your own shifts?',
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
