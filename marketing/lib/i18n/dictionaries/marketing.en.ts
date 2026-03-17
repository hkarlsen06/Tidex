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
        question: 'Do you have an iPhone app?',
        answers: [
          'Yes. Tidex is available as an iPhone app in the App Store.',
          'Your shifts, settings and subscription are tied to your account, so everything stays in sync in the app.',
        ],
      },
      {
        question: 'Can I still use the website?',
        answers: [
          'No. The old website has been retired because almost everyone used the iPhone app instead.',
          'Tidex is built by a solo developer, so the time goes where it helps the most. Right now that means the iPhone app, which is where the active users are.',
          'If you have an old website account or billing question, contact support and we will help manually.',
        ],
      },
      {
        question: 'How do breaks work?',
        answers: [
          'If you work more than 5.5 hours, the app automatically deducts a 30-minute break using the default rules most people need.',
          'If your workplace uses different rules, you can override break behavior in settings, including shifts that cross midnight.',
        ],
      },
      {
        question: 'How do overtime and extra pay work?',
        answers: [
          'Tell us which extra pay rules apply to you and Tidex handles the rest automatically. Evening pay from 18:00? Weekend pay? Set it up once in settings.',
          'When you log a shift, the calculator checks the date and time and adds the right extra pay on top of your base pay.',
        ],
      },
      {
        question: 'Can I download a pay report?',
        answers: [
          'Absolutely. Export every shift as PDF or Excel (CSV) any time, e.g. for payroll and timesheet reporting.',
          'Reports include working hours, breaks, supplements and total pay for each shift.',
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
