export const marketingNo = {
  meta: {
    title: 'Lønnskalkulator | Tidex',
    description: 'Få oversikt over lønn, tillegg og overtid med Tidex. En moderne lønnskalkulator som gir full kontroll.',
    ogTitle: 'Tidex | Timelønn',
    ogDescription: 'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med Tidex.',
    ogImageAlt: 'Tidex gir deg kontroll på lønnen din',
  },
  hero: {
    eyebrow: 'iPhone-app',
    title: 'Se hva vakten din er verdt',
    description: '…så du alltid vet hva du faktisk får utbetalt.',
    primaryCta: 'Se neste lønning',
    appStoreCta: 'Se neste lønning',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex-logo',
    logoLinkLabel: 'Tidex i App Store',
    screenshotAlt: 'Skjermbilde av Tidex iPhone-appen som viser dashbordet og vaktoversikten.',
    trustNote: 'Gratis å starte. Bygget for ekte arbeid.',
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Spørsmål og svar',
    description: 'Korte svar om lønn, pris og dataene dine.',
    docsLink: 'Slik regner Tidex ut lønn',
    contactLink: 'Spør oss om noe annet',
    items: [
      {
        question: 'Hva er Tidex?',
        answers: [
          'Tidex er en iPhone-app for deg som får timelønn. Appen regner ut hva hver vakt gir, så du vet hva neste lønning blir før den kommer.',
          'Du kan sammenligne tallet med lønnsslippen og oppdage feil tidlig.',
        ],
      },
      {
        question: 'Hva koster det?',
        answers: [
          'Ingenting. Alle funksjonene i Tidex er gratis, uten abonnement og uten reklame.',
        ],
      },
      {
        question: 'Hvordan kommer jeg i gang?',
        answers: [
          'Last ned appen og legg inn timelønn, tillegg og skatteprosent. Det gjør du bare én gang.',
          'Deretter legger du inn vaktene selv, eller importerer dem fra en kalenderfil (.ics) hvis arbeidsgiveren sender en.',
        ],
      },
      {
        question: 'Hvordan håndterer Tidex tillegg, overtid og pauser?',
        answers: [
          'Tillegg gjelder for timene de dekker, for eksempel kveld eller helg. Overtid og ubetalte pauser følger reglene du setter opp.',
          'Lønnsdokumentasjonen viser hver regel og hvordan Tidex bruker den.',
        ],
      },
      {
        question: 'Tar appen hensyn til skatt?',
        answers: [
          'Ja. Legg inn trekkprosenten fra skattekortet, så viser Tidex både brutto og netto lønn.',
          'Tidex håndterer også måneden med halv skatt.',
        ],
      },
      {
        question: 'Kan jeg dele vaktene mine med venner?',
        answers: [
          'Ja. Legg til venner i appen for å se når de jobber, og la dem se dine vakter. Du velger selv hvem du deler med.',
        ],
      },
      {
        question: 'Kan jeg eksportere vaktene mine?',
        answers: [
          'Ja. Eksporter en valgfri periode som PDF eller CSV fra innstillingene i appen.',
        ],
      },
      {
        question: 'Hvor lagres dataene mine?',
        answers: [
          'På servere vi drifter selv, leid fra netcup i Tyskland. Sikkerhetskopier blir lagret i EU.',
          'Vi lagrer vaktene, innstillingene og profilen din. Vi selger aldri dataene dine. Sletter du kontoen i appen, sletter vi dataene dine, og kopier i sikkerhetskopier forsvinner innen 28 dager.',
        ],
      },
      {
        question: 'Finnes Tidex for Android?',
        answers: [
          'Nei. Tidex finnes bare for iPhone.',
        ],
      },
    ],
  },
  socialProof: {
    eyebrow: 'Bygget for ekte vakter',
    heading: 'Slik gir det verdi',
    description: 'Brukere velger Tidex for forutsigbar beregning, tydeligere overtidsregler og enkle rapporter.',
    items: [
      {
        title: 'Åpen beregning',
        description: 'Hver linje i totalen er synlig, så du ser hvorfor lønnen blir som den blir.',
      },
      {
        title: 'Rapporter som brukes',
        description: 'Eksporter rene rapporter raskt når du trenger tall for lønnsoppfølging.',
      },
      {
        title: 'Rask i bruk',
        description: 'Sett opp reglene én gang, og få relevante estimater for hver vakt uten tung innsats.',
      },
    ],
  },
  ctaPrimary: {
    heading: 'Klar til å teste med dine egne vakter?',
    description: 'Opprett en konto gratis og få kontroll på tillegg, overtid og rapporter før neste lønning går ut.',
    button: 'Kom i gang gratis',
  },
  contact: {
    heading: 'Har du spørsmål?',
    description: 'Ta kontakt hvis du lurer på noe eller har tilbakemeldinger.',
    button: 'Ta kontakt',
    emailSubject: 'Kontakt fra Tidex',
    emailBody: 'Hei!\n\nJeg lurer på ...',
  },
  footer: {
    payrollDocs: 'Lønnsdokumentasjon',
    privacy: 'Personvernerklæring',
    terms: 'Vilkår for bruk',
    support: 'Support',
    copyright: '© 2026 Hjalmar Karlsen',
  },
} as const;
