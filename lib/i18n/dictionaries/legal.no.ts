export const legalNo = {
  modalTitle: 'Juridisk informasjon',
  modalDescription: 'Les gjennom våre vilkår og personvernerklæring',
  tabs: {
    terms: 'Vilkår for bruk',
    privacy: 'Personvernerklæring',
  },
  actions: {
    accept: 'Godtar',
    decline: 'Avslår',
  },
  contactEmail: 'contact@tidex.no',
  terms: {
    meta: {
      title: 'Vilkår for bruk — Tidex',
      description: 'Les vilkårene for bruk av Tidex og hva som forventes av brukere av tjenesten.',
    },
    title: 'Vilkår for bruk',
    lastUpdatedLabel: 'Sist oppdatert',
    dateLocale: 'nb-NO',
    sections: [
      {
        heading: '1. Aksept av vilkår',
        paragraphs: [
          'Ved å opprette en konto og bruke denne tjenesten, godtar du disse vilkårene.',
          'Tjenesten leveres av Tidex v/ Hjalmar Samuel Kristensen-Karlsen.',
        ],
      },
      {
        heading: '2. Beskrivelse av tjenesten',
        paragraphs: [
          'Tjenesten er et personlig skiftsporing- og lønnsutregningsverktøy. Vi tilbyr verktøy for å registrere arbeidstimer, beregne lønn basert på dine innstillinger og administrere skiftdata.',
        ],
        importantNote: {
          label: 'Viktig:',
          text: 'Lønnsberegninger er estimater basert på data du selv oppgir. Vi garanterer ikke nøyaktighet og anbefaler at du verifiserer alle beregninger med arbeidsgiver eller regnskapsfører.',
        },
      },
      {
        heading: '3. Alderskrav',
        paragraphs: [
          'Du må være minst 13 år gammel for å bruke tjenesten, i samsvar med norsk lovgivning om minste arbeidsalder.',
        ],
      },
      {
        heading: '4. Brukerkonto',
        list: [
          { text: 'Du er ansvarlig for å holde påloggingsinformasjonen din sikker.' },
          { text: 'Du er ansvarlig for all aktivitet under din konto.' },
          { text: 'Du må oppgi korrekt og oppdatert informasjon.' },
          { text: 'Hver bruker er uavhengig – det er ingen arbeidsgiver/arbeidstaker-forhold mellom brukere.' },
        ],
      },
      {
        heading: '5. Akseptabel bruk',
        paragraphs: ['Du samtykker i å ikke:'],
        list: [
          { text: 'Bruke tjenesten til ulovlige formål.' },
          { text: 'Forsøke å få uautorisert tilgang til andres kontoer eller data.' },
          { text: 'Forstyrre eller skade tjenestens funksjonalitet.' },
          { text: 'Automatisere tilgang til tjenesten uten uttrykkelig tillatelse.' },
          { text: 'Misbruke eller omgå betalingssystemet.' },
        ],
      },
      {
        heading: '6. Abonnement og betaling',
        list: [
          { text: 'Betaling håndteres gjennom Stripe.' },
          { text: 'Abonnementer fornyes automatisk med mindre du sier opp.' },
          { text: 'Vi forbeholder oss retten til å endre priser med 30 dagers varsel.' },
          { text: 'Refusjon gis etter individuell vurdering.' },
        ],
      },
      {
        heading: '7. Dine data og eierskap',
        list: [
          { text: 'Du eier alle data du registrerer i tjenesten.' },
          { text: 'Du gir oss tillatelse til å lagre og behandle dataene for å tilby tjenesten.' },
          { text: 'Vi lagrer kun rådata om skift – lønnsberegninger gjøres i sanntid på server eller enhet.' },
          { text: 'Ved sletting av konto fjernes alle data umiddelbart.' },
        ],
      },
      {
        heading: '8. Ansvarsbegrensning',
        paragraphs: ['Tjenesten leveres «som den er» uten garantier av noen slag. Vi er ikke ansvarlige for:'],
        list: [
          { text: 'Feil i lønnsberegninger eller tap som følge av disse.' },
          { text: 'Tap av data som følge av tekniske feil.' },
          { text: 'Nedetid eller utilgjengelighet av tjenesten.' },
          { text: 'Skader som følge av din bruk av tjenesten.' },
        ],
        closingParagraph: 'Du bruker tjenesten på eget ansvar. Vårt maksimale ansvar er begrenset til beløpet du har betalt de siste 12 månedene.',
      },
      {
        heading: '9. Oppsigelse',
        list: [
          { text: 'Du kan når som helst slette kontoen din via innstillinger.' },
          { text: 'Vi kan suspendere eller avslutte kontoen din ved brudd på vilkårene.' },
          { text: 'Ved oppsigelse mister du tilgang til alle data i systemet.' },
        ],
      },
      {
        heading: '10. Endringer i vilkårene',
        paragraphs: ['Vi kan oppdatere disse vilkårene. Vesentlige endringer varsles via e-post eller i tjenesten minst 30 dager før de trer i kraft. Fortsatt bruk etter endringer betyr aksept.'],
      },
      {
        heading: '11. Gjeldende lov',
        paragraphs: ['Disse vilkårene er underlagt norsk lov. Tvister løses i norske domstoler.'],
      },
      {
        heading: '12. Kontakt',
        paragraphs: ['Spørsmål om vilkårene kan sendes til contact@tidex.no.'],
      },
    ],
  },
  privacy: {
    meta: {
      title: 'Personvernerklæring — Tidex',
      description: 'Les om hvordan Tidex samler inn, bruker og beskytter dine personopplysninger.',
    },
    title: 'Personvernerklæring',
    lastUpdatedLabel: 'Sist oppdatert',
    dateLocale: 'nb-NO',
    sections: [
      {
        heading: '1. Ansvarlig',
        paragraphs: [
          'Tidex v/ Hjalmar Samuel Kristensen-Karlsen',
          'Kontakt: contact@tidex.no',
        ],
      },
      {
        heading: '2. Hvilke data vi samler inn',
        paragraphs: ['Vi samler inn følgende personopplysninger når du bruker tjenesten:'],
        list: [
          { boldLabel: 'Kontoinformasjon:', text: 'Fullt navn, e-postadresse eller telefonnummer og kryptert passord.' },
          { boldLabel: 'Skiftdata:', text: 'Arbeidstider, pauser, lønnsinnstillinger og relatert informasjon du registrerer.' },
          { boldLabel: 'Autentiseringsinformasjon:', text: 'Informasjon om økter (cookies) for å holde deg innlogget.' },
          { boldLabel: 'Betalingsinformasjon:', text: 'Behandles utelukkende av Stripe. Vi lagrer ikke kortinformasjon.' },
        ],
      },
      {
        heading: '3. Hvordan vi bruker dataene',
        paragraphs: ['Dine data brukes til:'],
        list: [
          { text: 'Tilby skiftsporing og lønnsutregning.' },
          { text: 'Autentisere og administrere kontoen din.' },
          { text: 'Behandle abonnementsbetalinger via Stripe.' },
          { text: 'Kommunisere med deg om tjenesten.' },
        ],
        importantNote: {
          label: 'Viktig:',
          text: 'All lønnsutregning skjer på server eller din enhet. Vi lagrer kun rådata om skift – ingen ferdige lønnsberegninger lagres.',
        },
      },
      {
        heading: '4. Datalagring og -behandling',
        list: [
          { boldLabel: 'Lagring:', text: 'All data lagres hos Supabase (PostgreSQL).' },
          { boldLabel: 'Oppbevaring:', text: 'Data oppbevares så lenge du har en aktiv konto. Vi garanterer ikke langtidsoppbevaring.' },
          { boldLabel: 'Sletting:', text: 'Ved sletting av konto fjernes alle data umiddelbart fra våre systemer.' },
        ],
      },
      {
        heading: '5. Tredjepartstjenester',
        paragraphs: ['Vi bruker følgende tredjepartstjenester som behandler persondata:'],
        list: [
          {
            boldLabel: 'Supabase:',
            text: 'Database og autentisering. Les deres {link}.',
            link: {
              href: 'https://supabase.com/privacy',
              text: 'personvernerklæring',
            },
          },
          {
            boldLabel: 'Stripe:',
            text: 'Betalingsbehandling. Les deres {link}.',
            link: {
              href: 'https://stripe.com/privacy',
              text: 'personvernerklæring',
            },
          },
          {
            boldLabel: 'Cloudflare Turnstile:',
            text: 'CAPTCHA-verifisering ved registrering. Les deres {link}.',
            link: {
              href: 'https://www.cloudflare.com/privacypolicy/',
              text: 'personvernerklæring',
            },
          },
        ],
        closingParagraph: 'Vi deler ikke dataene dine med andre tredjeparter.',
      },
      {
        heading: '6. Dine rettigheter',
        paragraphs: ['I henhold til GDPR har du rett til å:'],
        list: [
          { text: 'Få innsyn i hvilke data vi har om deg.' },
          { text: 'Få rettet uriktige opplysninger.' },
          { text: 'Få slettet dine data (sletting av konto).' },
          { text: 'Få dataene dine i et maskinlesbart format (dataportabilitet).' },
          { text: 'Trekke tilbake samtykke til behandling.' },
        ],
        closingParagraph: 'Kontakt oss på contact@tidex.no for å utøve disse rettighetene.',
      },
      {
        heading: '7. Sikkerhet',
        paragraphs: ['Vi bruker bransjestandard sikkerhetstiltak inkludert krypterte passordhash, HTTPS-kryptering og sikre autentiseringsmekanismer via Supabase.'],
      },
      {
        heading: '8. Endringer i personvernerklæringen',
        paragraphs: ['Vi kan oppdatere denne erklæringen. Vesentlige endringer varsles via e-post eller i tjenesten.'],
      },
      {
        heading: '9. Kontakt',
        paragraphs: ['Spørsmål om personvern kan sendes til contact@tidex.no.'],
      },
    ],
  },
  security: {
    meta: {
      title: 'Retningslinjer for sikkerhetsrapportering — Tidex',
      description: 'Hvordan rapportere sikkerhetssårbarheter til Tidex på en ansvarlig måte.',
    },
    title: 'Retningslinjer for sikkerhetsrapportering',
    lastUpdatedLabel: 'Sist oppdatert',
    dateLocale: 'nb-NO',
    sections: [
      {
        heading: '1. Oversikt',
        paragraphs: [
          'Vi tar sikkerheten til Tidex og våre brukere på alvor. Hvis du oppdager en sikkerhetssårbarhet, oppfordrer vi deg til å rapportere den på en ansvarlig måte.',
          'Denne policyen forklarer hvordan du rapporterer sårbarheter og hva du kan forvente fra oss.',
        ],
      },
      {
        heading: '2. Hvordan rapportere',
        paragraphs: [
          'Send rapporten din til contact@tidex.no med emnelinjen "Sikkerhetsrapport".',
          'Vennligst inkluder:',
        ],
        list: [
          { text: 'En tydelig beskrivelse av sårbarheten.' },
          { text: 'Steg for å reprodusere problemet.' },
          { text: 'Den potensielle konsekvensen hvis den utnyttes.' },
          { text: 'Eventuell proof-of-concept-kode eller skjermbilder, hvis tilgjengelig.' },
        ],
      },
      {
        heading: '3. Responstid',
        paragraphs: ['Når du rapporterer en sårbarhet:'],
        list: [
          { text: 'Vi sikter mot å bekrefte mottak innen 72 timer.' },
          { text: 'Vi sikter mot å gi en innledende vurdering innen 10 virkedager.' },
          { text: 'Tidslinjer for løsning avhenger av alvorlighetsgrad og kompleksitet.' },
        ],
        closingParagraph: 'Vi holder deg informert om fremdriften gjennom hele prosessen.',
      },
      {
        heading: '4. Trygg havn',
        paragraphs: [
          'Vi anser sikkerhetsforskning utført i samsvar med denne policyen som autorisert, og vil ikke forfølge rettslige skritt mot forskere som:',
        ],
        list: [
          { text: 'Handler i god tro og følger denne policyen.' },
          { text: 'Unngår å få tilgang til eller endre data som tilhører andre brukere.' },
          { text: 'Ikke forstyrrer eller forringer tjenesten.' },
          { text: 'Rapporterer sårbarheter raskt og ikke utnytter dem utover det som er nødvendig for å demonstrere problemet.' },
        ],
      },
      {
        heading: '5. Innenfor scope',
        paragraphs: ['Vi er interessert i sårbarheter som påvirker:'],
        list: [
          { text: 'Autentiserings- og autorisasjonsfeil.' },
          { text: 'Betalingsbehandlingssikkerhet.' },
          { text: 'API-sikkerhetsproblemer.' },
          { text: 'Dataeksponering eller lekkasje.' },
          { text: 'Cross-site scripting (XSS) og injeksjonssårbarheter.' },
          { text: 'Svakheter i sesjonshåndtering.' },
        ],
      },
      {
        heading: '6. Utenfor scope',
        paragraphs: ['Følgende anses ikke som gyldige sikkerhetsrapporter:'],
        list: [
          { text: 'Tjenestenektangrep (DoS).' },
          { text: 'Sosial manipulasjon eller phishing-forsøk.' },
          { text: 'Fysiske angrep mot infrastrukturen vår.' },
          { text: 'Sårbarheter i tredjepartstjenester vi ikke kontrollerer.' },
          { text: 'Problemer som krever fysisk tilgang til en brukers enhet.' },
          { text: 'Utdaterte nettlesere eller plugins.' },
        ],
      },
      {
        heading: '7. Håndtering av brukerdata',
        paragraphs: [
          'Hvis du oppdager en sårbarhet som eksponerer brukerdata:',
        ],
        list: [
          { text: 'Ikke få tilgang til, kopier eller lagre brukerdata utover det som er nødvendig for å demonstrere sårbarheten.' },
          { text: 'Slett alle brukerdata du måtte ha fått tilgang til så snart rapporten er sendt inn.' },
          { text: 'Ikke del brukerdata med tredjeparter.' },
        ],
      },
      {
        heading: '8. Koordinert offentliggjøring',
        paragraphs: [
          'Vi ber om at du gir oss rimelig tid til å håndtere sårbarheten før offentlig offentliggjøring.',
          'Vi sikter mot å løse kritiske problemer så raskt som mulig og vil koordinere med deg om tidspunkt for offentliggjøring.',
          'Hvis du ønsker å publisere funnene dine, vennligst kontakt oss først slik at vi kan sikre at brukerne er beskyttet.',
        ],
      },
      {
        heading: '9. Kontakt',
        paragraphs: ['Sikkerhetsrapporter og spørsmål sendes til contact@tidex.no.'],
      },
    ],
  },
} as const;
