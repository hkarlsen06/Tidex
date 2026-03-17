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
        question: 'Har dere en iPhone-app?',
        answers: [
          'Ja, Tidex finnes som app for iPhone, og du laster den ned i App Store.',
          'Vakter, innstillinger og abonnement er knyttet til kontoen din, så alt holder seg oppdatert i appen.',
        ],
      },
      {
        question: 'Kan jeg fortsatt bruke nettsiden?',
        answers: [
          'Nei. Den gamle nettsiden er avviklet fordi nesten alle brukte iPhone-appen.',
          'Tidex bygges av én utvikler, så tiden brukes der den hjelper flest. Akkurat nå betyr det iPhone-appen, som er der de aktive brukerne er.',
          'Hvis du har en gammel nettkonto eller spørsmål om tidligere webbetalinger, hjelper support deg manuelt.',
        ],
      },
      {
        question: 'Hvordan fungerer pauser?',
        answers: [
          'Jobber du over 5,5 timer, trekker appen automatisk 30 minutter pause med standardregler som passer for de fleste.',
          'Hvis arbeidsgiveren din har andre regler, kan du overstyre pausereglene i innstillingene, også for vakter som går over midnatt.',
        ],
      },
      {
        question: 'Hvordan fungerer overtid og tillegg?',
        answers: [
          'Du registrerer først hvilke tillegg som gjelder hos deg, så regner vi resten ut automatisk. Kveldstillegg fra 18:00? Helgetillegg? Ett oppsett i innstillingene.',
          'Når du legger inn en vakt, ser kalkulatoren på tid og dag og legger til riktige tillegg på toppen av grunnlønna.',
        ],
      },
      {
        question: 'Kan jeg laste ned en lønnsrapport?',
        answers: [
          'Ja. Du kan laste ned alle vaktene dine som PDF eller Excel (CSV) når som helst, for eksempel til lønnsslipp og timeseddel.',
          'Rapporten viser arbeidstimer, pauser, tillegg og total utbetaling for hver vakt.',
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
  ctaPrimary: {
    heading: 'Klar for å teste vaktene dine?',
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
    copyright: '© 2026 Hjalmar Kristensen-Karlsen',
  },
} as const;
