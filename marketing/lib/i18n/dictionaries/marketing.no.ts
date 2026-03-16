export const marketingNo = {
  meta: {
    title: 'Tidex — Regn ut lønna di - gratis!',
    description: 'Få oversikt over lønn, tillegg og overtid med Tidex. En moderne lønnskalkulator som gir full kontroll.',
    ogTitle: 'Tidex — Regn ut lønna di - gratis!',
    ogDescription: 'Hold styr på lønnen din, planlegg vakter og håndter tillegg automatisk med Tidex.',
    ogImageAlt: 'Tidex — Kontroll på lønnen din',
  },
  hero: {
    eyebrow: 'Native iPhone-app',
    title: 'Se hva vakten din er verdt.',
    description: 'Tidex beregner lønn, tillegg og tariff i sanntid — slik at du aldri overraskes på lønnsdagen.',
    primaryCta: 'Åpne appen',
    appStoreCta: 'Last ned fra App Store',
    secondaryCta: 'FAQ',
    imageAlt: 'Tidex-logo',
    screenshotAlt: 'Skjermbilde av Tidex iPhone-appen som viser dashbordet og vaktoversikten.',
    trustNote: 'Gratis å starte. Bygget for ekte turnusarbeid.',
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Vanlige spørsmål',
    description: 'Alt du trenger å vite om vakter, rapporter og hvordan dataene dine behandles.',
    items: [
      {
        question: 'Hva koster det? Er det gratis?',
        answers: [
          'Ja, du kan komme i gang gratis med kjernefunksjonene.',
          'Skaleres du opp i bruken, gir Pro-abonnementet ubegrensede måneder for bare 29 kr i måneden.',
        ],
      },
      {
        question: 'Finnes det en native iOS-app?',
        answers: [
          'Ja, Tidex har en native iOS-app laget i SwiftUI som ligger i App Store.',
          'iOS-appen bruker samme sikre backend og kontosystem som resten av Tidex, så vakter, innstillinger og abonnement holdes synkronisert.',
        ],
      },
      {
        question: 'Er nettappen fortsatt tilgjengelig?',
        answers: [
          'Nei. Den gamle nettappen er avviklet fordi den ble brukt for lite til at det ga mening å vedlikeholde den ved siden av den native appen.',
          'Tidex bygges av én utvikler, så jeg må bruke tiden der den hjelper flest. Akkurat nå betyr det iOS-appen, som er der de aktive brukerne er.',
          'Hvis du har en gammel nettkonto eller spørsmål om tidligere webbetalinger, hjelper support deg manuelt.',
        ],
      },
      {
        question: 'Hvordan håndteres pauser og pausetrekk?',
        answers: [
          'Vi regner smart: Jobber du over 5,5 timer, trekker vi automatisk 30 minutter pause — med standardregler som gjelder for de fleste stillinger.',
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
        question: 'Kan jeg laste ned lønnsrapporter?',
        answers: [
          'Ja. Du kan laste ned alle vaktene dine som PDF eller Excel (CSV) når som helst, for eksempel til lønnsslipp og timeseddel.',
          'Rapporten viser arbeidstimer, pauser, tillegg og total utbetaling for hver vakt.',
        ],
      },
      {
        question: 'Hvor lagres dataene mine?',
        answers: [
          'Dataene dine lagres i sikre Supabase-tabeller knyttet til kontoen din.',
          'iOS-appen bruker lokal-first-lagring og synkroniserer mot samme backend, slik at dataene dine er tilgjengelige på enheten samtidig som de er knyttet til kontoen din.',
        ],
      },
      {
        question: 'Er dataene mine trygge?',
        answers: [
          'Selvfølgelig. Vi tar personvern seriøst. Vaktdata sendes til serveren ved innlogging og synkronisering, ikke tilfeldig.',
          'Vi lagrer kun det som trengs for å gi funksjonalitet: vakter, innstillinger og profilinformasjon.',
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
