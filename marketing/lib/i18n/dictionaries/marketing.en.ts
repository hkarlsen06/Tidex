export const marketingEn = {
  meta: {
    title: 'Pay Calculator | Tidex',
    description: 'Stay on top of salary, supplements and overtime with Tidex. A modern wage calculator that keeps you in control.',
    ogTitle: 'Tidex | Hourly Pay',
    ogDescription: 'Track your salary, plan shifts and handle supplements automatically with Tidex.',
    ogImageAlt: 'Tidex gives you full control over your salary',
  },
  hero: {
    eyebrow: 'iPhone app',
    title: 'Know what your shift is worth',
    description: '...so you always know what you will actually get paid.',
    primaryCta: 'See next paycheck',
    appStoreCta: 'See next paycheck',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex logo',
    logoLinkLabel: 'Tidex on the App Store',
    screenshotAlt: 'Screenshot of the Tidex iPhone app showing the dashboard and shifts overview.',
    trustNote: 'Free to start. Built for real shift work.',
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Questions and answers',
    description: 'Short answers about pay, price and your data.',
    docsLink: 'How Tidex calculates pay',
    contactLink: 'Ask us something else',
    items: [
      {
        question: 'What is Tidex?',
        answers: [
          'Tidex is an iPhone app for people paid by the hour. It works out what each shift pays, so you know your next paycheck before it arrives.',
          'You can compare that number with your payslip and spot mistakes early.',
        ],
      },
      {
        question: 'What does it cost?',
        answers: [
          'Nothing. Every feature in Tidex is free, with no subscription and no ads.',
        ],
      },
      {
        question: 'How do I get started?',
        answers: [
          'Download the app and enter your hourly rate, supplements and tax percentage. You only do this once.',
          'Then add your shifts by hand, or import them from a calendar file (.ics) if your employer sends one.',
        ],
      },
      {
        question: 'How does Tidex handle supplements, overtime and breaks?',
        answers: [
          'Supplements apply to the hours they cover, such as evenings or weekends. Overtime and unpaid breaks follow the rules you set.',
          'The payroll documentation lists each rule and how Tidex applies it.',
        ],
      },
      {
        question: 'Does it take tax into account?',
        answers: [
          'Yes. Enter the withholding percentage from your tax deduction card, and Tidex shows both gross and net pay.',
          'Tidex also handles the half-tax month, when Norwegian employers withhold only half the usual tax.',
        ],
      },
      {
        question: 'Can I share my shifts with friends?',
        answers: [
          'Yes. Add friends in the app to see when they work, and let them see your schedule. You choose who you share with.',
        ],
      },
      {
        question: 'Can I export my shifts?',
        answers: [
          'Yes. Export any period as a PDF or CSV file from the app settings.',
        ],
      },
      {
        question: 'Where is my data stored?',
        answers: [
          'On servers we run ourselves, rented from netcup in Germany. Backups stay in the EU.',
          'We store your shifts, settings and profile. We never sell your data. If you delete your account in the app, we delete your data, and backup copies expire within 28 days.',
        ],
      },
      {
        question: 'Is Tidex available on Android?',
        answers: [
          'No. Tidex is only available for iPhone.',
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
    button: 'Get started for free',
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
    support: 'Support',
    copyright: '© 2026 Hjalmar Karlsen',
  },
} as const;
