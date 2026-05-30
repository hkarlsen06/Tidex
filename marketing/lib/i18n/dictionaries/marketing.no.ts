export const marketingNo = {
  meta: {
    title: 'Lønnskalkulator | Tidex',
    description: 'Få oversikt over lønn, tillegg og overtid med Tidex. En moderne lønnskalkulator som gir full kontroll.',
    ogTitle: 'Tidex | Timelønn',
    ogDescription: 'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med Tidex.',
    ogImageAlt: 'Tidex — Kontroll på lønnen din',
  },
  hero: {
    eyebrow: 'iPhone-app',
    title: 'Se hva vakten din er verdt',
    description: '…så du alltid vet hva du faktisk får utbetalt.',
    primaryCta: 'Se neste lønning',
    appStoreCta: 'Se neste lønning',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex-logo',
    screenshotAlt: 'Skjermbilde av Tidex iPhone-appen som viser dashbordet og vaktoversikten.',
    trustNote: 'Gratis å starte. Bygget for ekte arbeid.',
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Vanlige spørsmål',
    description: 'Alt du trenger å vite om vakter, rapporter og hvordan dataene dine behandles.',
    items: [
      {
        question: 'Hva er Tidex, og hvorfor bør jeg bruke det?',
        answers: [
          'Tidex er en iPhone-app for timelønnede som vil vite hva hver vakt faktisk er verdt før lønning.',
          'Du får et tydelig estimat av lønn, tillegg, overtid og pauser på ett sted, så du kan planlegge bedre, oppdage feil og få mer kontroll på inntekten din.',
        ],
      },
      {
        question: 'Hva koster Tidex?',
        answers: [
          'Du kan komme i gang gratis med kjernefunksjonene.',
          'Hvis du vil ha mer, koster Pro 29 kr i måneden med ubegrenset historikk.',
        ],
      },
      {
        question: 'Hvordan registrerer jeg vakter og får riktig utbetaling?',
        answers: [
          'Legg inn grunnlønn, relevante tillegg og pausevalg én gang i innstillingene.',
          'Deretter legger du inn vakter, og Tidex regner ut utbetaling med samme regler hver gang, slik at tallene blir forutsigbare.',
        ],
      },
      {
        question: 'Hvordan blir pauser, overtid og tillegg beregnet?',
        answers: [
          'Appen bruker reglene du har satt opp for overtid, pauser og tillegg før den viser totalen.',
          'De fleste starter med standardregler, og justerer deretter hvis arbeidsgiveren har egne bestemmelser.',
        ],
      },
      {
        question: 'Kan jeg laste ned lønnsrapport fra appen?',
        answers: [
          'Ja. Du kan eksportere alle vaktene som PDF eller CSV når du trenger et ryddig utgangspunkt.',
          'Rapportene kan brukes ved lønnsoppfølging og eget økonomisk admin.',
        ],
      },
      {
        question: 'Hvor lagres dataene mine?',
        answers: [
          'Dataene dine lagres sikkert og er knyttet til kontoen din.',
          'Appen synkroniserer dataene dine, så de er tilgjengelige på enheten din og følger deg når du logger inn.',
        ],
      },
      {
        question: 'Er dataene mine trygge?',
        answers: [
          'Ja. Vi tar personvern seriøst, og vaktdataene dine sendes bare når det trengs for innlogging og synkronisering.',
          'Vi lagrer bare det som trengs for at appen skal fungere: vakter, innstillinger og profilinformasjon.',
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
    button: 'Start nå – gratis',
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
    copyright: '© 2026 Hjalmar Karlsen',
  },
} as const;
