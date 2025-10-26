export const marketingNo = {
  meta: {
    title: 'Tidex — Regn ut lønna di - gratis!',
    description: 'Få oversikt over lønn, tillegg og overtid med Tidex. En moderne lønnskalkulator som gir full kontroll.',
    ogTitle: 'Tidex — Regn ut lønna di - gratis!',
    ogDescription: 'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med Tidex.',
    ogImageAlt: 'Tidex — Kontroll på lønnen din',
  },
  hero: {
    title: 'Få kontroll over lønnen din',
    description: 'Lønnskalkulatoren som tar vakter, tillegg og tariff på alvor. Excel er over.',
    highlights: ['Nøyaktig', 'Rask', 'Privat', 'Stabil'],
    primaryCta: 'Åpne appen',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex-logo',
  },
  features: {
    eyebrow: 'Hvorfor Tidex?',
    heading: 'Laget for deg som vil ha full kontroll',
    description: 'Våre viktigste funksjoner er designet for å gjøre lønnsberegningen enkel, nøyaktig og pålitelig.',
    items: [
      {
        icon: 'shield',
        title: 'Beskytt deg mot dårlig lønn',
        description: 'Se hva du vil tjene før du takker ja til ei ekstravakt.',
      },
      {
        icon: 'zap',
        title: 'Automatiske tillegg',
        description: 'Tillegg regnes automatisk ut for hver vakt.',
      },
      {
        icon: 'clock',
        title: 'Smidige utregninger',
        description: 'Håndterer pauser, delte skift og vakter som går over midnatt uten stress.',
      },
      {
        icon: 'layers',
        title: 'Rapporter klare',
        description: 'Last ned komplette PDF-rapporter og behold full oversikt måned for måned.',
      },
    ],
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Vanlige spørsmål',
    description: 'Alt du trenger å vite om vakter, rapporter og hvordan dataene dine behandles.',
    items: [
      {
        question: 'Hvordan håndteres pauser og pausetrekk?',
        answers: [
          'Vi regner ut lønna di smart! Hvis du jobber over 5,5 timer, trekker vi automatisk 30 minutter for pause, akkurat som de fleste arbeidsgivere gjør.',
          'Jobber du nattskift eller lange vakter? Ingen problem! Kalkulatoren takler alt fra vanlige arbeidsdager til skift som går over midnatt. Du kan også justere pausereglene i innstillingene hvis arbeidsplassen din har andre regler.',
        ],
      },
      {
        question: 'Hvordan fungerer overtid og tillegg?',
        answers: [
          'Du forteller oss hvilke tillegg du har rett på, så regner vi ut alt automatisk! Har du kveldstillegg fra 18:00? Helgetillegg på lørdager og søndager? Bare sett opp reglene én gang i innstillingene.',
          'Når du registrerer en vakt, ser kalkulatoren på tidspunktet og dagen, og legger til riktige tillegg oppå grunnlønna di. Enkelt og greit.',
        ],
      },
      {
        question: 'Hvor lagres dataene mine?',
        answers: [
          'Trygt og smart! Alle innstillingene dine lagres hos databasen vår hos Supabase.',
          'Når du logger inn, synkroniserer vi også vaktene og innstillingene dine til skyen. Da kan du bytte mellom telefon og PC, og alt er tilgjengelig overalt. Ingen data forsvinner!',
        ],
      },
      {
        question: 'Kan jeg laste ned lønnsrapporter?',
        answers: [
          'Absolutt! Du kan laste ned alle vaktene dine som en PDF eller Excel-fil (CSV) når som helst. Perfekt når du skal levere timelistene eller bare vil ha oversikt over måneden.',
          'Rapporten viser alle detaljene: arbeidstimer, pauser, tillegg og totallønn for hver vakt.',
        ],
      },
      {
        question: 'Hva koster det? Er det gratis?',
        answers: [
          'Ja, det er helt gratis å starte! Du kan bruke kalkulatoren så mye du vil, men du har kun plass til vakter for én måned om gangen. Det holder for de fleste.',
          'Trenger du mer? Vi har Pro-abonnementet som gir deg ubegrenset antall måneder. Det koster bare 29 kr i måneden – mindre enn en kopp kaffe i uka!',
        ],
      },
      {
        question: 'Kan jeg bruke den på mobil som en app?',
        answers: [
          'Ja! Du kan installere kalkulatoren som en app på telefonen din. Besøk nettsiden i Safari eller Chrome, så kan du «legge til på hjemskjerm».',
          'Den fungerer som en vanlig app – med eget ikon og alt. Du trenger internett for å synke data, men de fleste funksjonene virker selv om nettet er tregt.',
        ],
      },
      {
        question: 'Er dataene mine trygge?',
        answers: [
          'Selvfølgelig! Vi er supernøye med personvern. Dataene dine (som vakter og timelønn) sendes bare til serveren når du velger å logge inn – aldri ellers.',
          'Vi lagrer bare det som trengs for at kalkulatoren skal virke: vaktene dine, innstillingene og profilbildet. Ingenting mer!',
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
    privacy: 'Personvernerklæring',
    terms: 'Vilkår for bruk',
    copyright: '© 2025 Hjalmar Kristensen-Karlsen',
  },
} as const;
