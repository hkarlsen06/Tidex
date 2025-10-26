export const legalEn = {
  modalTitle: 'Legal information',
  modalDescription: 'Read through our terms of use and privacy policy',
  tabs: {
    terms: 'Terms of use',
    privacy: 'Privacy policy',
  },
  actions: {
    accept: 'Accept',
    decline: 'Decline',
  },
  contactEmail: 'contact@tidex.no',
  terms: {
    meta: {
      title: 'Terms of use — Tidex',
      description: 'Understand the rules for using Tidex and what we expect from every user.',
    },
    title: 'Terms of use',
    lastUpdatedLabel: 'Last updated',
    dateLocale: 'en-US',
    sections: [
      {
        heading: '1. Acceptance of terms',
        paragraphs: [
          'By creating an account and using this service, you accept these terms.',
          'The service is provided by Tidex / Hjalmar Samuel Kristensen-Karlsen.',
        ],
      },
      {
        heading: '2. Description of the service',
        paragraphs: [
          'The service is a personal shift-tracking and salary calculation tool. We provide tools to log hours, calculate pay based on your settings and manage shift data.',
        ],
        importantNote: {
          label: 'Important:',
          text: 'Salary calculations are estimates based on the data you provide. We do not guarantee accuracy and recommend verifying every result with your employer or accountant.',
        },
      },
      {
        heading: '3. Age requirement',
        paragraphs: [
          'You must be at least 13 years old to use the service, in line with Norwegian labour regulations.',
        ],
      },
      {
        heading: '4. User account',
        list: [
          { text: 'You are responsible for keeping your login information secure.' },
          { text: 'You are responsible for all activity under your account.' },
          { text: 'You must provide correct and up-to-date information.' },
          { text: 'Every user is independent — there is no employer/employee relationship between users.' },
        ],
      },
      {
        heading: '5. Acceptable use',
        paragraphs: ['You agree not to:'],
        list: [
          { text: 'Use the service for illegal purposes.' },
          { text: 'Attempt to gain unauthorised access to other accounts or data.' },
          { text: 'Disrupt or harm the functionality of the service.' },
          { text: 'Automate access to the service without explicit permission.' },
          { text: 'Abuse or bypass the payment system.' },
        ],
      },
      {
        heading: '6. Subscription and payment',
        list: [
          { text: 'Payments are handled through Stripe.' },
          { text: 'Subscriptions renew automatically unless you cancel.' },
          { text: 'We reserve the right to change prices with 30 days’ notice.' },
          { text: 'Refunds are evaluated individually.' },
        ],
      },
      {
        heading: '7. Your data and ownership',
        list: [
          { text: 'You own every piece of data you add to the service.' },
          { text: 'You allow us to store and process the data so we can operate the service.' },
          { text: 'We only store raw shift data — salary calculations happen in real time on the server or your device.' },
          { text: 'When you delete your account, all data is removed immediately.' },
        ],
      },
      {
        heading: '8. Limitation of liability',
        paragraphs: ['The service is provided “as is” without warranties of any kind. We are not liable for:'],
        list: [
          { text: 'Errors in salary calculations or losses that result from them.' },
          { text: 'Loss of data caused by technical issues.' },
          { text: 'Downtime or unavailability of the service.' },
          { text: 'Any damage arising from your use of the service.' },
        ],
        closingParagraph: 'You use the service at your own risk. Our maximum liability is limited to the amount you paid during the last 12 months.',
      },
      {
        heading: '9. Termination',
        list: [
          { text: 'You may delete your account at any time from the settings area.' },
          { text: 'We may suspend or terminate your account if you break these terms.' },
          { text: 'When the account is closed you lose access to every piece of data in the system.' },
        ],
      },
      {
        heading: '10. Changes to the terms',
        paragraphs: ['We may update these terms. Significant changes are announced via email or in the product at least 30 days before they take effect. Continued use after that means you accept the changes.'],
      },
      {
        heading: '11. Governing law',
        paragraphs: ['These terms are governed by Norwegian law. Disputes are handled by Norwegian courts.'],
      },
      {
        heading: '12. Contact',
        paragraphs: ['Questions about the terms can be sent to contact@tidex.no.'],
      },
    ],
  },
  privacy: {
    meta: {
      title: 'Privacy policy — Tidex',
      description: 'Learn how Tidex collects, uses and protects your personal data.',
    },
    title: 'Privacy policy',
    lastUpdatedLabel: 'Last updated',
    dateLocale: 'en-US',
    sections: [
      {
        heading: '1. Controller',
        paragraphs: [
          'Tidex / Hjalmar Samuel Kristensen-Karlsen',
          'Contact: contact@tidex.no',
        ],
      },
      {
        heading: '2. Data we collect',
        paragraphs: ['We collect the following personal data when you use the service:'],
        list: [
          { boldLabel: 'Account information:', text: 'Full name, email address or phone number, and encrypted password.' },
          { boldLabel: 'Shift data:', text: 'Working hours, breaks, salary settings and related information you register.' },
          { boldLabel: 'Authentication data:', text: 'Session (cookie) information that keeps you logged in.' },
          { boldLabel: 'Payment data:', text: 'Handled solely by Stripe. We do not store card information.' },
        ],
      },
      {
        heading: '3. How we use the data',
        paragraphs: ['Your data is used to:'],
        list: [
          { text: 'Provide shift tracking and salary calculations.' },
          { text: 'Authenticate and manage your account.' },
          { text: 'Process subscription payments via Stripe.' },
          { text: 'Communicate with you about the service.' },
        ],
        importantNote: {
          label: 'Important:',
          text: 'All salary calculations happen on the server or your device. We only store raw shift data — no final salary results are saved.',
        },
      },
      {
        heading: '4. Storage and processing',
        list: [
          { boldLabel: 'Storage:', text: 'All data is stored with Supabase (PostgreSQL).' },
          { boldLabel: 'Retention:', text: 'Data is kept for as long as you maintain an active account. We do not guarantee long-term archival.' },
          { boldLabel: 'Deletion:', text: 'If you delete your account, every piece of data is removed immediately from our systems.' },
        ],
      },
      {
        heading: '5. Third-party services',
        paragraphs: ['We rely on the following third parties that process personal data:'],
        list: [
          {
            boldLabel: 'Supabase:',
            text: 'Database and authentication. Read their {link}.',
            link: {
              href: 'https://supabase.com/privacy',
              text: 'privacy policy',
            },
          },
          {
            boldLabel: 'Stripe:',
            text: 'Payment processing. Read their {link}.',
            link: {
              href: 'https://stripe.com/privacy',
              text: 'privacy policy',
            },
          },
          {
            boldLabel: 'Cloudflare Turnstile:',
            text: 'Captcha verification during signup. Read their {link}.',
            link: {
              href: 'https://www.cloudflare.com/privacypolicy/',
              text: 'privacy policy',
            },
          },
        ],
        closingParagraph: 'We do not share your data with any other third parties.',
      },
      {
        heading: '6. Your rights',
        paragraphs: ['Under GDPR you have the right to:'],
        list: [
          { text: 'Access the data we store about you.' },
          { text: 'Correct inaccurate information.' },
          { text: 'Delete your data (account deletion).' },
          { text: 'Receive your data in a machine-readable format (data portability).' },
          { text: 'Withdraw consent to processing.' },
        ],
        closingParagraph: 'Contact us at contact@tidex.no to exercise your rights.',
      },
      {
        heading: '7. Security',
        paragraphs: ['We use industry-standard security measures including encrypted password hashes, HTTPS encryption and secure authentication through Supabase.'],
      },
      {
        heading: '8. Changes to this policy',
        paragraphs: ['We may update this notice. Significant changes will be announced via email or inside the service.'],
      },
      {
        heading: '9. Contact',
        paragraphs: ['Questions about privacy can be sent to contact@tidex.no.'],
      },
    ],
  },
} as const;
