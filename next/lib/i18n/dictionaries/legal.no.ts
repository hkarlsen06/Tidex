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
    lastUpdatedDate: '2026-03-08',
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
          { text: 'Bruke chat, deling, profilinformasjon, bilder eller andre sosiale funksjoner til å trakassere, mobbe, true, spamme, stalke eller utgi deg for å være andre brukere.' },
          { text: 'Dele hatefult, seksuelt utnyttende, voldelig eller på annen måte støtende innhold gjennom meldinger, vedlegg, profilinformasjon eller andre flater for brukergenerert innhold i Tidex.' },
        ],
        closingParagraph: 'Det er nulltoleranse for støtende innhold og abusive brukere. Vi kan undersøke rapportert atferd, begrense funksjoner, fjerne innhold, suspendere meldings- eller delingstilgang, blokkere brukere eller avslutte kontoer når vi mottar misbruksrapporter eller på annen måte blir kjent med misbruk.',
      },
      {
        heading: '6. Abonnement og betaling',
        paragraphs: [
          'Tidex tilbyr betalte abonnementer som gir tilgang til premium-funksjoner. Betalingsvilkårene varierer avhengig av plattform:',
        ],
        list: [
          { boldLabel: 'Nettside:', text: 'Abonnementer kjøpt via tidex.no håndteres av Stripe. Du kan administrere og si opp via kontoinnstillingene.' },
          { boldLabel: 'iOS-appen:', text: 'Abonnementer kjøpt i iOS-appen håndteres av Apple via In-App Purchase. Abonnementer fornyes automatisk med mindre du sier opp minst 24 timer før gjeldende periode utløper. Du administrerer og sier opp abonnementet i App Store-innstillingene på enheten din (Innstillinger → Apple-ID → Abonnementer).' },
        ],
        subsections: [
          {
            subheading: 'Automatisk fornyelse',
            text: 'Alle abonnementer fornyes automatisk med mindre de sies opp før neste fakturaperiode.',
          },
          {
            subheading: 'Prisendringer',
            text: 'For abonnementer kjøpt via nettsiden, vil vi varsle deg om prisendringer. For iOS-abonnementer følger prisendringer Apples prosesser, og du kan bli bedt om å godta nye priser før fornyelse.',
          },
          {
            subheading: 'Refusjoner',
            text: 'For abonnementer kjøpt via nettsiden vurderes refusjoner individuelt – kontakt oss på contact@tidex.no. For iOS-kjøp håndteres refusjoner av Apple i henhold til App Store-retningslinjene. Besøk reportaproblem.apple.com for å be om refusjon.',
          },
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
        closingParagraph: 'Hvis vi mottar en rapport om støtende innhold eller misbruk, kan vi undersøke det relevante innholdet, begrense tilgang, fjerne innhold, blokkere de involverte brukerne eller suspendere eller avslutte kontoen til den som har brutt reglene.',
      },
      {
        heading: '10. Vilkår for iOS-appen',
        paragraphs: [
          'Følgende tilleggsvilkår gjelder når du bruker Tidex iOS-applikasjonen lastet ned fra Apple App Store:',
        ],
        subsections: [
          {
            subheading: 'Bekreftelse',
            text: 'Du bekrefter at disse vilkårene er inngått mellom deg og Tidex, ikke med Apple Inc. («Apple»). Tidex, ikke Apple, er eneansvarlig for Tidex-appen og dens innhold.',
          },
          {
            subheading: 'Lisensomfang',
            text: 'Lisensen som gis til deg er begrenset til en ikke-overførbar lisens til å bruke Tidex-appen på Apple-merkede enheter som du eier eller kontrollerer, i samsvar med bruksreglene i Apple Media Services-vilkårene. Appen kan brukes av andre kontoer knyttet til deg via Familiedeling eller volumkjøp.',
          },
          {
            subheading: 'Vedlikehold og støtte',
            text: 'Tidex er eneansvarlig for vedlikehold og støtte for appen. Apple har ingen forpliktelse til å levere vedlikeholds- eller støttetjenester.',
          },
          {
            subheading: 'Garanti',
            text: 'Tidex er eneansvarlig for eventuelle produktgarantier, uttrykkelige eller underforståtte. Dersom appen ikke oppfyller gjeldende garantier, kan du varsle Apple, og Apple vil refundere kjøpsprisen (hvis aktuelt). I den grad loven tillater det, har Apple ingen andre garantiforpliktelser. Alle andre garantikrav er Tidex sitt eneansvar.',
          },
          {
            subheading: 'Produktkrav',
            text: 'Tidex, ikke Apple, er ansvarlig for å håndtere eventuelle krav knyttet til appen, inkludert produktansvarskrav, krav om at appen ikke oppfyller juridiske eller regulatoriske krav, og krav under forbrukervernlovgivning eller personvernlovgivning.',
          },
          {
            subheading: 'Immaterielle rettigheter',
            text: 'Ved eventuelle tredjepartskrav om at appen krenker immaterielle rettigheter, er Tidex, ikke Apple, eneansvarlig for undersøkelse, forsvar, forlik og oppgjør av slike krav.',
          },
          {
            subheading: 'Tredjepartsbegunstiget',
            text: 'Du bekrefter og godtar at Apple og dets datterselskaper er tredjepartsbegunstigede av disse vilkårene. Ved din aksept har Apple rett til å håndheve disse vilkårene mot deg som tredjepartsbegunstiget.',
          },
        ],
      },
      {
        heading: '11. Juridisk overholdelse',
        paragraphs: [
          'Ved å bruke tjenesten bekrefter og garanterer du at: (i) du ikke befinner deg i et land underlagt embargo fra amerikanske myndigheter eller utpekt som et «terrorstøttende» land; og (ii) du ikke er oppført på noen liste over forbudte eller begrensede parter fra amerikanske myndigheter.',
        ],
      },
      {
        heading: '12. Tredjepartstjenester',
        paragraphs: [
          'Når du bruker Tidex-appen, må du overholde eventuelle gjeldende tredjepartsavtaler, for eksempel avtalen din med mobiloperatøren.',
        ],
      },
      {
        heading: '13. Endringer i vilkårene',
        paragraphs: ['Vi kan oppdatere disse vilkårene. Vesentlige endringer varsles via e-post eller i tjenesten før de trer i kraft. Fortsatt bruk etter endringer betyr aksept.'],
      },
      {
        heading: '14. Gjeldende lov',
        paragraphs: ['Disse vilkårene er underlagt norsk lov. Tvister løses i norske domstoler.'],
      },
      {
        heading: '15. Kontakt',
        paragraphs: [
          'For spørsmål, klager eller krav angående Tidex, kontakt oss på:',
        ],
        list: [
          { boldLabel: 'Utvikler:', text: 'Tidex v/ Hjalmar Samuel Kristensen-Karlsen' },
          { boldLabel: 'Adresse:', text: 'Lensmannsveien 8, 9515 Alta, Norge' },
          { boldLabel: 'E-post:', text: 'contact@tidex.no' },
        ],
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
    lastUpdatedDate: '2026-03-08',
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
          { boldLabel: 'Vennemeldinger:', text: 'Meldinger, svarreferanser, bildevedlegg, misbruksrapporter, blokkeringer, trådmetadata og lese-/mute-status når du bruker vennemeldinger.' },
          { boldLabel: 'Autentiseringsinformasjon:', text: 'Informasjon om økter (cookies) for å holde deg innlogget.' },
          { boldLabel: 'Betalingsinformasjon:', text: 'Behandles av Stripe (nettsidekjøp) eller Apple (iOS-kjøp i appen). Vi lagrer ikke kortinformasjon.' },
          { boldLabel: 'AI-assistentdata:', text: 'Når du bruker Wagey AI-assistenten, blir meldingene du sender (inkludert tekst og bilder), visningsnavnet ditt og skiftdata som hentes under samtalen behandlet av en tredjeparts AI-tjeneste (se punkt 5).' },
          { boldLabel: 'Varslingsmetadata:', text: 'Hvis du aktiverer pushvarsler, kan varslingspayloaden inneholde avsenderidentitet, begrenset meldingsforhåndsvisning, skjermbildevarsler og trådidentifikatorer slik at appen kan vise og åpne riktig samtale.' },
        ],
      },
      {
        heading: '3. Hvordan vi bruker dataene',
        paragraphs: ['Dine data brukes til:'],
        list: [
          { text: 'Tilby skiftsporing og lønnsutregning.' },
          { text: 'Tilby vennemeldinger, bildevedlegg, skjermbildevarsler, misbruksrapportering, sikkerhetsfunksjoner og blokkering av brukere.' },
          { text: 'Autentisere og administrere kontoen din.' },
          { text: 'Behandle abonnementsbetalinger via Stripe (nettside) eller Apple (iOS-appen).' },
          { text: 'Kommunisere med deg om tjenesten.' },
          { text: 'Tilby AI-drevet assistanse gjennom Wagey-funksjonen, inkludert å svare på spørsmål om skiftene dine, hjelpe med å administrere skift og beregne lønn. Dette krever sending av relevante data til en tredjeparts AI-tjeneste (se punkt 5).' },
          { text: 'Behandle misbruksrapporter, håndheve reglene våre og beskytte brukere og tjenesten mot misbruk.' },
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
          { boldLabel: 'Sikkerhetsgjennomgang:', text: 'Hvis innhold rapporteres eller knyttes til misbruk, kan autoriserte behandlere gjennomgå relevante meldinger, vedlegg, kontometadata og rapportdata for å undersøke og håndheve reglene våre.' },
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
            text: 'Betalingsbehandling for nettsidekjøp. Les deres {link}.',
            link: {
              href: 'https://stripe.com/privacy',
              text: 'personvernerklæring',
            },
          },
          {
            boldLabel: 'Apple:',
            text: 'In-App Purchase og betalingsbehandling for iOS-kjøp. Les deres {link}.',
            link: {
              href: 'https://www.apple.com/legal/privacy/',
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
          {
            boldLabel: 'OpenAI:',
            text: 'Wagey AI-assistenten drives av OpenAI. Når du bruker Wagey, kan meldingene du skriver, eventuelle bilder du legger ved, visningsnavnet ditt og skiftdata som hentes under samtalen (som arbeidstider, pauser og lønnsinnstillinger) sendes til OpenAI for behandling. Ved behov kan Wagey også bruke OpenAI web search for å hente relevant offentlig informasjon fra nettet. Disse dataene sendes kun når du aktivt bruker Wagey-funksjonen og har gitt ditt uttrykkelige samtykke. OpenAI behandler data i samsvar med deres {link}.',
            link: {
              href: 'https://openai.com/policies/privacy-policy',
              text: 'personvernerklæring',
            },
          },
        ],
        closingParagraph: 'Data deles kun med OpenAI når du aktivt bruker Wagey AI-assistenten og har gitt ditt uttrykkelige samtykke. Ingen data deles med andre tredjeparter utover de som er oppført ovenfor.',
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
    lastUpdatedDate: '2026-02-21',
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
