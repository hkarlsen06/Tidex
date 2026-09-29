export const marketingNo = {
  meta: {
    title: 'Lønnskalkulator | Tidex',
    description: 'Få oversikt over lønn, tillegg og overtid med Tidex. En moderne lønnskalkulator som gir full kontroll.',
    ogTitle: 'Tidex | Timelønn',
    ogDescription: 'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med Tidex.',
    ogImageAlt: 'Tidex gir deg kontroll på lønnen din',
  },
  hero: {
    title: 'Hva er den ekstravakten egentlig verdt?',
    titleEmphasis: 'egentlig',
    description: 'Tidex viser hva du ligger an til å tjene, før lønningsdagen.',
    appStoreCta: 'Last ned gratis',
    note: 'Gratis · Uten reklame',
    imageAlt: 'Tidex-logo',
    logoLinkLabel: 'Tidex i App Store',
    screenshotAlt: 'Tidex på en iPhone, som viser 22 400 kr etter skatt i september og neste utbetaling.',
  },
  story: {
    heading: 'Inni appen',
    panels: [
      'Si ja til ekstravakter og vit hva de gir. Legg en vakt i kalenderen og se hva den betyr for måneden.',
      'Alle jobbene i én oversikt. Følg med på timer og inntekt over tid, uten løse notater og regnestykker.',
      'Vit hvor pengene kommer fra. Se hvordan beløpet er satt sammen, og ha noe å sjekke lønnsslippen mot.',
      'Tiden din er verdt å holde styr på. Begynn med din neste vakt.',
    ],
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
  ctaPrimary: {
    heading: 'Prøv med dine egne vakter',
    description: 'Alle funksjoner er gratis, uten reklame og abonnement. Tidex finnes bare for iPhone.',
  },
  contact: {
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
