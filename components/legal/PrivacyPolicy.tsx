export function PrivacyPolicy() {
  return (
    <div className="prose prose-sm max-w-none dark:prose-invert space-y-6">
      <div>
        <h1>Personvernerklæring</h1>
        <p className="text-text-muted" suppressHydrationWarning>Sist oppdatert: {new Date().toLocaleDateString('nb-NO')}</p>
      </div>

      <div>
        <h2>1. Ansvarlig</h2>
        <p>
          KKarlsen Productions v/ Hjalmar Samuel Kristensen-Karlsen
          <br />
          Kontakt: <a href="mailto:kkarlsen06@kkarlsen.dev">kkarlsen06@kkarlsen.dev</a>
        </p>
      </div>

      <div>
        <h2>2. Hvilke data vi samler inn</h2>
        <p>Vi samler inn følgende personopplysninger når du bruker tjenesten:</p>
        <ul>
          <li><strong>Kontoinformasjon:</strong> Fullt navn, e-postadresse eller telefonnummer, og kryptert passord</li>
          <li><strong>Skiftdata:</strong> Arbeidstider, pauser, lønnsinnstillinger og relatert informasjon du registrerer</li>
          <li><strong>Autentiseringsinformasjon:</strong> Øktkakeinformasjon (cookies) for å holde deg innlogget</li>
          <li><strong>Betalingsinformasjon:</strong> Behandles utelukkende av Stripe. Vi lagrer ikke kortinformasjon</li>
        </ul>
      </div>

      <div>
        <h2>3. Hvordan vi bruker dataene</h2>
        <p>Dine data brukes til:</p>
        <ul>
          <li>Tilby skiftsporing og lønnsutregning</li>
          <li>Autentisere og administrere din konto</li>
          <li>Behandle abonnementsbetalinger via Stripe</li>
          <li>Kommunisere med deg om tjenesten</li>
        </ul>
        <p>
          <strong>Viktig:</strong> All lønnsutregning skjer på server eller din enhet. Vi lagrer kun rådata om skift –
          ingen ferdige lønnsberegninger lagres.
        </p>
      </div>

      <div>
        <h2>4. Datalagring og -behandling</h2>
        <ul>
          <li><strong>Lagring:</strong> All data lagres hos Supabase (en PostgreSQL-database)</li>
          <li><strong>Oppbevaring:</strong> Data oppbevares så lenge du har en aktiv konto. Vi garanterer ikke langtidsoppbevaring</li>
          <li><strong>Sletting:</strong> Ved sletting av konto fjernes alle dine data umiddelbart fra våre systemer</li>
        </ul>
      </div>

      <div>
        <h2>5. Tredjepartstjenester</h2>
        <p>Vi bruker følgende tredjepartstjenester som behandler persondata:</p>
        <ul>
          <li>
            <strong>Supabase:</strong> Database og autentisering. Les deres{' '}
            <a href="https://supabase.com/privacy" target="_blank" rel="noopener noreferrer">
              personvernerklæring
            </a>
          </li>
          <li>
            <strong>Stripe:</strong> Betalingsbehandling. Les deres{' '}
            <a href="https://stripe.com/privacy" target="_blank" rel="noopener noreferrer">
              personvernerklæring
            </a>
          </li>
          <li>
            <strong>Cloudflare Turnstile:</strong> CAPTCHA-verifisering ved registrering. Les deres{' '}
            <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener noreferrer">
              personvernerklæring
            </a>
          </li>
        </ul>
        <p>Vi deler ikke dine data med andre tredjeparter.</p>
      </div>

      <div>
        <h2>6. Dine rettigheter</h2>
        <p>I henhold til GDPR har du rett til å:</p>
        <ul>
          <li>Få innsyn i hvilke data vi har om deg</li>
          <li>Få rettet uriktige opplysninger</li>
          <li>Få slettet dine data (sletting av konto)</li>
          <li>Få dataene dine i et maskinlesbart format (dataportabilitet)</li>
          <li>Trekke tilbake samtykke til behandling</li>
        </ul>
        <p>
          Kontakt oss på <a href="mailto:kkarlsen06@kkarlsen.dev">kkarlsen06@kkarlsen.dev</a> for å utøve disse rettighetene.
        </p>
      </div>

      <div>
        <h2>7. Sikkerhet</h2>
        <p>
          Vi bruker industry-standard sikkerhetstiltak inkludert krypterte passordhash, HTTPS-kryptering,
          og sikre autentiseringsmekanismer via Supabase.
        </p>
      </div>

      <div>
        <h2>8. Endringer i personvernerklæringen</h2>
        <p>
          Vi kan oppdatere denne erklæringen. Vesentlige endringer vil varsles via e-post eller i tjenesten.
        </p>
      </div>

      <div>
        <h2>9. Kontakt</h2>
        <p>
          Spørsmål om personvern kan sendes til:{' '}
          <a href="mailto:kkarlsen06@kkarlsen.dev">kkarlsen06@kkarlsen.dev</a>
        </p>
      </div>
    </div>
  );
}
