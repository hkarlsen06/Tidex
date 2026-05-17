export const devEn = {
  nav: {
    home: 'Home',
    projects: 'Projects',
    about: 'About',
    contact: 'Contact',
  },
  home: {
    hero: {
      greeting: 'Hi, I am',
      name: 'Hjalmar Karlsen',
      title: 'iOS Developer',
      tagline: 'Building native Apple platform apps with SwiftUI, local-first data, and production-grade sync',
      cta: 'Get in touch',
      viewWork: 'View my work',
    },
    skills: {
      title: 'What I work with',
      frontend: 'Native iOS',
      backend: 'Data & sync',
      tools: 'Apple platform',
    },
  },
  projects: {
    title: 'My Projects',
    subtitle: 'Production Apple platform work and supporting product surfaces',
    tidexIos: {
      title: 'Tidex for iOS',
      subtitle: 'Native iOS app',
      description: 'A production SwiftUI app for tracking work shifts, calculating wages, and syncing local data with Supabase. The app uses SwiftData repositories, bidirectional sync with conflict handling, StoreKit subscriptions, notifications, widgets, live activities, watchOS support, and a custom payroll calculation engine.',
      tech: 'Technologies',
      features: 'Key Features',
      feature1: 'SwiftUI interface with shared design components',
      feature2: 'Local-first SwiftData storage and repository layer',
      feature3: 'Supabase auth, realtime, RLS-backed sync, and conflict handling',
      feature4: 'StoreKit 2 subscriptions, JWS handling, and entitlement caching',
      feature5: 'WidgetKit, ActivityKit, watchOS, share extension, and notifications',
      viewAppStore: 'View on App Store',
    },
    tidexWeb: {
      title: 'Tidex Marketing Site',
      subtitle: 'Public website & legal surface',
      description: 'The public Tidex website that now owns acquisition, support, legal pages, and payroll documentation after the retirement of the old web app.',
      tech: 'Technologies',
      features: 'Key Features',
      feature1: 'Localized landing experience',
      feature2: 'Static support and legal pages',
      feature3: 'Payroll engine documentation',
      feature4: 'Cloudflare Pages friendly export',
      feature5: 'App Store-first product messaging',
      viewLive: 'Visit tidex.no',
    },
  },
  about: {
    title: 'About Me',
    subtitle: 'Native iOS developer focused on real product architecture',
    bio: {
      intro: 'I mainly build native iOS apps now. Tidex is where I spend most of my engineering energy: SwiftUI screens, SwiftData persistence, local-first repositories, Supabase sync, StoreKit subscriptions, widgets, live activities, watchOS, and notification flows.',
      passion: 'I like product engineering where UI polish and hard data problems meet. The work I enjoy most is making Apple-platform features feel simple while the architecture underneath handles offline use, sync, payroll calculations, auth, and edge cases reliably.',
    },
    skills: {
      title: 'Technical Skills',
      frontend: {
        title: 'Native iOS',
        list: 'Swift, SwiftUI, SwiftData, MVVM, async/await, Observation patterns, Charts, localized app experiences',
      },
      backend: {
        title: 'Data & Sync',
        list: 'Local-first repositories, Supabase Auth/PostgREST/Realtime/Storage/Functions, PostgreSQL, RLS, conflict handling, offline support',
      },
      tools: {
        title: 'Apple Platform',
        list: 'StoreKit 2, WidgetKit, ActivityKit, WatchConnectivity, UserNotifications, App Intents, share extensions, App Store release workflows',
      },
    },
    approach: {
      title: 'My Approach',
      description: 'I care about apps that remain fast, understandable, and resilient as they grow. I keep business logic out of views, use local data as the source of truth, and make platform features feel native rather than bolted on.',
    },
  },
  contact: {
    title: "Let's Work Together",
    subtitle: 'I am available for iOS work and Apple platform projects',
    email: {
      title: 'Email',
      cta: 'Send me an email',
    },
    github: {
      title: 'GitHub',
      cta: 'View my profile',
    },
    message: 'Looking for help with a native iOS app, SwiftUI feature work, sync architecture, or App Store-ready product polish? Get in touch.',
  },
  footer: {
    rights: 'All rights reserved',
    builtWith: 'Built with',
  },
};
