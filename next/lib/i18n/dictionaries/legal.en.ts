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
    lastUpdatedDate: '2026-02-21',
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
        paragraphs: [
          'Tidex offers paid subscriptions that unlock premium features. Payment terms vary by platform:',
        ],
        list: [
          { boldLabel: 'Website:', text: 'Subscriptions purchased via tidex.no are handled by Stripe. You can manage and cancel via your account settings.' },
          { boldLabel: 'iOS app:', text: 'Subscriptions purchased in the iOS app are handled by Apple via In-App Purchase. Subscriptions renew automatically unless you cancel at least 24 hours before the current period ends. You manage and cancel your subscription in the App Store settings on your device (Settings → Apple ID → Subscriptions).' },
        ],
        subsections: [
          {
            subheading: 'Auto-renewal',
            text: 'All subscriptions renew automatically unless cancelled before the next billing period.',
          },
          {
            subheading: 'Price changes',
            text: "For subscriptions purchased via the website, we will notify you of price changes. For iOS subscriptions, price changes follow Apple's processes, and you may be asked to consent to new pricing before renewal.",
          },
          {
            subheading: 'Refunds',
            text: 'For subscriptions purchased via the website, refunds are evaluated individually—contact us at contact@tidex.no. For iOS purchases, refunds are handled by Apple under App Store policies. Visit reportaproblem.apple.com to request a refund.',
          },
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
        heading: '10. iOS app terms',
        paragraphs: [
          'The following additional terms apply when you use the Tidex iOS application downloaded from the Apple App Store:',
        ],
        subsections: [
          {
            subheading: 'Acknowledgement',
            text: 'You acknowledge that these terms are between you and Tidex only, not with Apple Inc. ("Apple"). Tidex, not Apple, is solely responsible for the Tidex app and its content.',
          },
          {
            subheading: 'Scope of license',
            text: 'The license granted to you is limited to a non-transferable license to use the Tidex app on any Apple-branded devices that you own or control, as permitted by the Usage Rules in the Apple Media Services Terms and Conditions. The app may be accessed by other accounts associated with you via Family Sharing or volume purchasing.',
          },
          {
            subheading: 'Maintenance and support',
            text: 'Tidex is solely responsible for providing maintenance and support for the app. Apple has no obligation to provide any maintenance or support services.',
          },
          {
            subheading: 'Warranty',
            text: 'Tidex is solely responsible for any product warranties, whether express or implied. If the app fails to conform to any applicable warranty, you may notify Apple and Apple will refund the purchase price (if any). To the maximum extent permitted by law, Apple has no other warranty obligation. Any other warranty claims are Tidex\'s sole responsibility.',
          },
          {
            subheading: 'Product claims',
            text: 'Tidex, not Apple, is responsible for addressing any claims relating to the app, including product liability claims, claims that the app fails to meet legal or regulatory requirements, and claims under consumer protection or privacy legislation.',
          },
          {
            subheading: 'Intellectual property',
            text: 'In the event of any third-party claim that the app infringes intellectual property rights, Tidex, not Apple, is solely responsible for the investigation, defense, settlement, and discharge of such claims.',
          },
          {
            subheading: 'Third-party beneficiary',
            text: 'You acknowledge and agree that Apple and its subsidiaries are third-party beneficiaries of these terms. Upon your acceptance, Apple has the right to enforce these terms against you as a third-party beneficiary.',
          },
        ],
      },
      {
        heading: '11. Legal compliance',
        paragraphs: [
          'By using the service, you represent and warrant that: (i) you are not located in a country subject to a U.S. Government embargo or designated as a "terrorist supporting" country; and (ii) you are not listed on any U.S. Government list of prohibited or restricted parties.',
        ],
      },
      {
        heading: '12. Third-party services',
        paragraphs: [
          'When using the Tidex app, you must comply with any applicable third-party terms of agreement, such as your mobile data service agreement.',
        ],
      },
      {
        heading: '13. Changes to the terms',
        paragraphs: ['We may update these terms. Significant changes are announced via email or in the product before they take effect. Continued use after that means you accept the changes.'],
      },
      {
        heading: '14. Governing law',
        paragraphs: ['These terms are governed by Norwegian law. Disputes are handled by Norwegian courts.'],
      },
      {
        heading: '15. Contact',
        paragraphs: [
          'For questions, complaints, or claims regarding Tidex, contact us at:',
        ],
        list: [
          { boldLabel: 'Developer:', text: 'Tidex / Hjalmar Samuel Kristensen-Karlsen' },
          { boldLabel: 'Address:', text: 'Lensmannsveien 8, 9515 Alta, Norway' },
          { boldLabel: 'Email:', text: 'contact@tidex.no' },
        ],
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
    lastUpdatedDate: '2026-02-21',
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
          { boldLabel: 'Payment data:', text: 'Handled by Stripe (website purchases) or Apple (iOS in-app purchases). We do not store card information.' },
          { boldLabel: 'AI assistant data:', text: 'When you use the Wagey AI assistant, the messages you send (including text and images), your display name, and shift data retrieved during the conversation are processed by a third-party AI service (see section 5).' },
        ],
      },
      {
        heading: '3. How we use the data',
        paragraphs: ['Your data is used to:'],
        list: [
          { text: 'Provide shift tracking and salary calculations.' },
          { text: 'Authenticate and manage your account.' },
          { text: 'Process subscription payments via Stripe (website) or Apple (iOS app).' },
          { text: 'Communicate with you about the service.' },
          { text: 'Provide AI-powered assistance through the Wagey feature, including answering questions about your shifts, helping manage shifts, and calculating wages. This requires sending relevant data to a third-party AI service (see section 5).' },
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
            text: 'Payment processing for website purchases. Read their {link}.',
            link: {
              href: 'https://stripe.com/privacy',
              text: 'privacy policy',
            },
          },
          {
            boldLabel: 'Apple:',
            text: 'In-App Purchase and payment processing for iOS purchases. Read their {link}.',
            link: {
              href: 'https://www.apple.com/legal/privacy/',
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
          {
            boldLabel: 'Anthropic (Claude AI):',
            text: 'The Wagey AI assistant is powered by Claude, a large language model developed by Anthropic. When you use Wagey, the following data is sent to Anthropic\'s API for processing: the messages you type, any images you attach, your display name, and shift data retrieved during the conversation (such as working hours, breaks, and wage settings). This data is sent only when you actively use the Wagey feature and have given your explicit consent. Anthropic processes data in accordance with their {link}.',
            link: {
              href: 'https://www.anthropic.com/privacy',
              text: 'privacy policy',
            },
          },
        ],
        closingParagraph: 'Data is only shared with Anthropic when you actively use the Wagey AI assistant and have given your explicit consent. No data is shared with any other third parties beyond those listed above.',
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
  security: {
    meta: {
      title: 'Security Disclosure Policy — Tidex',
      description: 'How to report security vulnerabilities to Tidex responsibly.',
    },
    title: 'Security Disclosure Policy',
    lastUpdatedLabel: 'Last updated',
    lastUpdatedDate: '2025-01-10',
    dateLocale: 'en-US',
    sections: [
      {
        heading: '1. Overview',
        paragraphs: [
          'We take the security of Tidex and our users seriously. If you discover a security vulnerability, we encourage you to report it responsibly.',
          'This policy explains how to report vulnerabilities and what you can expect from us.',
        ],
      },
      {
        heading: '2. How to report',
        paragraphs: [
          'Send your report to contact@tidex.no with the subject line "Security Report".',
          'Please include:',
        ],
        list: [
          { text: 'A clear description of the vulnerability.' },
          { text: 'Steps to reproduce the issue.' },
          { text: 'The potential impact if exploited.' },
          { text: 'Any proof-of-concept code or screenshots, if available.' },
        ],
      },
      {
        heading: '3. Response timeline',
        paragraphs: ['When you report a vulnerability:'],
        list: [
          { text: 'We aim to acknowledge receipt within 72 hours.' },
          { text: 'We aim to provide an initial assessment within 10 business days.' },
          { text: 'Resolution timelines depend on severity and complexity.' },
        ],
        closingParagraph: 'We will keep you informed of our progress throughout the process.',
      },
      {
        heading: '4. Safe harbor',
        paragraphs: [
          'We consider security research conducted in accordance with this policy to be authorised and will not pursue legal action against researchers who:',
        ],
        list: [
          { text: 'Act in good faith and follow this policy.' },
          { text: 'Avoid accessing or modifying data belonging to other users.' },
          { text: 'Do not disrupt or degrade the service.' },
          { text: 'Report vulnerabilities promptly and do not exploit them beyond what is necessary to demonstrate the issue.' },
        ],
      },
      {
        heading: '5. In scope',
        paragraphs: ['We are interested in vulnerabilities affecting:'],
        list: [
          { text: 'Authentication and authorisation flaws.' },
          { text: 'Payment processing security.' },
          { text: 'API security issues.' },
          { text: 'Data exposure or leakage.' },
          { text: 'Cross-site scripting (XSS) and injection vulnerabilities.' },
          { text: 'Session management weaknesses.' },
        ],
      },
      {
        heading: '6. Out of scope',
        paragraphs: ['The following are not considered valid security reports:'],
        list: [
          { text: 'Denial of service (DoS) attacks.' },
          { text: 'Social engineering or phishing attempts.' },
          { text: 'Physical attacks against our infrastructure.' },
          { text: 'Vulnerabilities in third-party services we do not control.' },
          { text: 'Issues requiring physical access to a user\'s device.' },
          { text: 'Outdated browsers or plugins.' },
        ],
      },
      {
        heading: '7. Handling user data',
        paragraphs: [
          'If you discover a vulnerability that exposes user data:',
        ],
        list: [
          { text: 'Do not access, copy, or store user data beyond what is necessary to demonstrate the vulnerability.' },
          { text: 'Delete any user data you may have accessed as soon as the report is submitted.' },
          { text: 'Do not share user data with third parties.' },
        ],
      },
      {
        heading: '8. Coordinated disclosure',
        paragraphs: [
          'We ask that you give us reasonable time to address the vulnerability before any public disclosure.',
          'We aim to resolve critical issues as quickly as possible and will coordinate with you on disclosure timing.',
          'If you wish to publish your findings, please contact us first so we can ensure users are protected.',
        ],
      },
      {
        heading: '9. Contact',
        paragraphs: ['Security reports and questions should be sent to contact@tidex.no.'],
      },
    ],
  },
} as const;
