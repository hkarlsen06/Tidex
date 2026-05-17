export const devNo = {
  nav: {
    home: 'Hjem',
    projects: 'Prosjekter',
    about: 'Om meg',
    contact: 'Kontakt',
  },
  home: {
    hero: {
      greeting: 'Hei, jeg er',
      name: 'Hjalmar Karlsen',
      title: 'iOS-utvikler',
      tagline: 'Bygger native Apple-plattformapper med SwiftUI, lokal data og produksjonsklar synk',
      cta: 'Ta kontakt',
      viewWork: 'Se arbeidet mitt',
    },
    skills: {
      title: 'Dette jobber jeg med',
      frontend: 'Native iOS',
      backend: 'Data og synk',
      tools: 'Apple-plattformen',
    },
  },
  projects: {
    title: 'Mine prosjekter',
    subtitle: 'Produksjonsarbeid for Apple-plattformen og støttende produktflater',
    tidexIos: {
      title: 'Tidex for iOS',
      subtitle: 'Native iOS-app',
      description: 'En produksjonsapp i SwiftUI for å føre vakter, beregne lønn og synkronisere lokal data med Supabase. Appen bruker SwiftData-repositories, toveis synk med konflikthåndtering, StoreKit-abonnement, varsler, widgets, live activities, watchOS-støtte og en egen lønnsberegningsmotor.',
      tech: 'Teknologier',
      features: 'Nøkkelfunksjoner',
      feature1: 'SwiftUI-grensesnitt med delte designkomponenter',
      feature2: 'Lokal-først SwiftData-lagring og repository-lag',
      feature3: 'Supabase auth, realtime, RLS-basert synk og konflikthåndtering',
      feature4: 'StoreKit 2-abonnement, JWS-håndtering og entitlement-cache',
      feature5: 'WidgetKit, ActivityKit, watchOS, share extension og varsler',
      viewAppStore: 'Se på App Store',
    },
    tidexWeb: {
      title: 'Tidex markedsføringsnettsted',
      subtitle: 'Offentlig nettsted og juridisk flate',
      description: 'Det offentlige Tidex-nettstedet som nå eier anskaffelse, support, juridiske sider og lønnsdokumentasjon etter at den gamle nettappen ble avviklet.',
      tech: 'Teknologier',
      features: 'Nøkkelfunksjoner',
      feature1: 'Lokalisert landingsopplevelse',
      feature2: 'Statiske support- og juridiske sider',
      feature3: 'Dokumentasjon av lønnsmotoren',
      feature4: 'Klar for eksport til Cloudflare Pages',
      feature5: 'App Store-først-produktbudskap',
      viewLive: 'Besøk tidex.no',
    },
  },
  about: {
    title: 'Om meg',
    subtitle: 'Native iOS-utvikler med fokus på ekte produktarkitektur',
    bio: {
      intro: 'Jeg bygger hovedsakelig native iOS-apper nå. Tidex er der jeg legger mest av utviklingsarbeidet mitt: SwiftUI-skjermer, SwiftData-lagring, lokal-først repositories, Supabase-synk, StoreKit-abonnement, widgets, live activities, watchOS og varslingsflyter.',
      passion: 'Jeg liker produktutvikling der polert UI møter vanskelige dataproblemer. Det mest interessante arbeidet er å få Apple-plattformfunksjoner til å føles enkle, mens arkitekturen under håndterer frakoblet bruk, synk, lønnsberegning, auth og edge cases stabilt.',
    },
    skills: {
      title: 'Tekniske ferdigheter',
      frontend: {
        title: 'Native iOS',
        list: 'Swift, SwiftUI, SwiftData, MVVM, async/await, Observation-mønstre, Charts og lokaliserte appopplevelser',
      },
      backend: {
        title: 'Data og synk',
        list: 'Lokal-først repositories, Supabase Auth/PostgREST/Realtime/Storage/Functions, PostgreSQL, RLS, konflikthåndtering og frakoblet støtte',
      },
      tools: {
        title: 'Apple-plattformen',
        list: 'StoreKit 2, WidgetKit, ActivityKit, WatchConnectivity, UserNotifications, App Intents, share extensions og App Store-releaseflyt',
      },
    },
    approach: {
      title: 'Min tilnærming',
      description: 'Jeg bryr meg om apper som holder seg raske, forståelige og robuste når de vokser. Jeg holder forretningslogikk ute av views, bruker lokal data som kilde til sannhet og lar plattformfunksjoner føles native i stedet for påklistret.',
    },
  },
  contact: {
    title: 'La oss samarbeide',
    subtitle: 'Jeg er tilgjengelig for iOS-arbeid og Apple-plattformprosjekter',
    email: {
      title: 'E-post',
      cta: 'Send meg en e-post',
    },
    github: {
      title: 'GitHub',
      cta: 'Se min profil',
    },
    message: 'Trenger du hjelp med en native iOS-app, SwiftUI-funksjoner, synkarkitektur eller App Store-klar produktpolish? Ta kontakt.',
  },
  footer: {
    rights: 'Alle rettigheter reservert',
    builtWith: 'Bygget med',
  },
};
