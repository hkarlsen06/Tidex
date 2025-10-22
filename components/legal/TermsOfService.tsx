export function TermsOfService() {
  return (
    <div className="prose prose-sm max-w-none dark:prose-invert">
      <h1>Vilkår for bruk</h1>
      <p className="text-text-muted">Sist oppdatert: {new Date().toLocaleDateString('nb-NO')}</p>

      <h2>1. Aksept av vilkår</h2>
      <p>
        Ved å opprette en konto og bruke denne tjenesten, godtar du disse vilkårene.
        Tjenesten leveres av KKarlsen Productions v/ Hjalmar Samuel Kristensen-Karlsen.
      </p>

      <h2>2. Beskrivelse av tjenesten</h2>
      <p>
        Tjenesten er et personlig skiftsporing- og lønnsutregningsverktøy. Vi tilbyr verktøy for å registrere
        arbeidstimer, beregne lønn basert på dine innstillinger, og administrere skiftdata.
      </p>
      <p>
        <strong>Viktig:</strong> Lønnsberegninger er estimater basert på data du selv oppgir. Vi garanterer ikke
        nøyaktighet og anbefaler at du verifiserer alle beregninger med din arbeidsgiver eller regnskapsfører.
      </p>

      <h2>3. Alderskrav</h2>
      <p>
        Du må være minst 13 år gammel for å bruke tjenesten, i samsvar med norsk lovgivning om minste arbeidsalder.
      </p>

      <h2>4. Brukerkonto</h2>
      <ul>
        <li>Du er ansvarlig for å holde påloggingsinformasjonen din sikker</li>
        <li>Du er ansvarlig for all aktivitet under din konto</li>
        <li>Du må oppgi korrekt og oppdatert informasjon</li>
        <li>Hver bruker er uavhengig – det er ingen arbeidsgiver/arbeidstaker-forhold mellom brukere</li>
      </ul>

      <h2>5. Akseptabel bruk</h2>
      <p>Du samtykker i å ikke:</p>
      <ul>
        <li>Bruke tjenesten til ulovlige formål</li>
        <li>Forsøke å få uautorisert tilgang til andres kontoer eller data</li>
        <li>Forstyrre eller skade tjenestens funksjonalitet</li>
        <li>Automatisere tilgang til tjenesten uten uttrykkelig tillatelse</li>
        <li>Misbruke eller omgå betalingssystemet</li>
      </ul>

      <h2>6. Abonnement og betaling</h2>
      <ul>
        <li>Betaling håndteres gjennom Stripe</li>
        <li>Abonnementer fornyes automatisk med mindre du sier opp</li>
        <li>Vi forbeholder oss retten til å endre priser med 30 dagers varsel</li>
        <li>Refusjon gis etter individuell vurdering</li>
      </ul>

      <h2>7. Dine data og eierskap</h2>
      <ul>
        <li>Du eier alle data du registrerer i tjenesten</li>
        <li>Du gir oss tillatelse til å lagre og behandle dataene for å tilby tjenesten</li>
        <li>Vi lagrer kun rådata om skift – lønnsberegninger gjøres i sanntid på server/enhet</li>
        <li>Ved sletting av konto fjernes alle dine data umiddelbart</li>
      </ul>

      <h2>8. Ansvarsbegrensning</h2>
      <p>Tjenesten leveres "som den er" uten garantier av noen slag. Vi er ikke ansvarlige for:</p>
      <ul>
        <li>Feil i lønnsberegninger eller tap som følge av disse</li>
        <li>Tap av data som følge av tekniske feil</li>
        <li>Nedetid eller utilgjengelighet av tjenesten</li>
        <li>Skader som følge av din bruk av tjenesten</li>
      </ul>
      <p>
        Du bruker tjenesten på eget ansvar. Vårt maksimale ansvar er begrenset til beløpet du har betalt for
        tjenesten de siste 12 månedene.
      </p>

      <h2>9. Oppsigelse</h2>
      <ul>
        <li>Du kan når som helst slette din konto via innstillinger</li>
        <li>Vi kan suspendere eller avslutte din konto ved brudd på vilkårene</li>
        <li>Ved oppsigelse mister du tilgang til all data i systemet</li>
      </ul>

      <h2>10. Endringer i vilkårene</h2>
      <p>
        Vi kan oppdatere disse vilkårene. Vesentlige endringer varsles via e-post eller i tjenesten minst
        30 dager før de trer i kraft. Fortsatt bruk etter endringer betyr aksept.
      </p>

      <h2>11. Gjeldende lov</h2>
      <p>
        Disse vilkårene er underlagt norsk lov. Tvister løses i norske domstoler.
      </p>

      <h2>12. Kontakt</h2>
      <p>
        Spørsmål om vilkårene kan sendes til:{' '}
        <a href="mailto:kkarlsen06@kkarlsen.dev">kkarlsen06@kkarlsen.dev</a>
      </p>
    </div>
  );
}
