import Link from 'next/link';
import { Clock, Layers, Shield, Zap } from 'lucide-react';
import { Button } from '@appui/Button';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import ViewportHeightSetter from '../components/ViewportHeightSetter';

const heroHighlights = ['Nøyaktig', 'Rask', 'Privat', 'Stabil'] as const;

const features = [
  {
    icon: Shield,
    title: 'Beskytt deg mot dårlig lønn',
    description: 'Se hva du vil tjene før du takker ja til ei ekstravakt.',
  },
  {
    icon: Zap,
    title: 'Automatiske tillegg',
    description: 'Tillegg regnes automatisk ut for hver vakt.',
  },
  {
    icon: Clock,
    title: 'Smidige utregninger',
    description: 'Håndterer pauser, delte skift og vakter som går over midnatt uten stress.',
  },
  {
    icon: Layers,
    title: 'Rapporter klare',
    description: 'Last ned komplette PDF-rapporter og behold full oversikt måned for måned.',
  },
] as const;

const faqs = [
  {
    question: 'Hvordan håndteres pauser og pausetrekk?',
    answer:
      'Vi regner ut lønna di smart! Hvis du jobber over 5,5 timer, trekker vi automatisk 30 minutter for pause, akkurat som de fleste arbeidsgivere gjør.\n\nJobber du nattskift eller lange vakter? Ingen problem! Kalkulatoren takler alt fra vanlige arbeidsdager til skift som går over midnatt. Du kan også justere pausereglene i innstillingene hvis arbeidsplassen din har andre regler.',
  },
  {
    question: 'Hvordan fungerer overtid og tillegg?',
    answer:
      'Du forteller oss hvilke tillegg du har rett på, så regner vi ut alt automatisk! Har du kveldstillegg fra 18:00? Helgetillegg på lørdager og søndager? Bare sett opp reglene én gang i innstillingene.\n\nNår du registrerer en vakt, ser kalkulatoren på tidspunktet og dagen, og legger til riktige tillegg oppå grunnlønna di. Enkelt og greit.',
  },
  {
    question: 'Hvor lagres dataene mine?',
    answer:
      'Trygt og smart! Alle innstillingene dine lagres hos databasen vår hos Supabase\n\nNår du logger inn, synkroniserer vi også vaktene og innstillingene dine til skyen. Da kan du bytte mellom telefon og PC, og alt er tilgjengelig overalt. Ingen data forsvinner!',
  },
  {
    question: 'Kan jeg laste ned lønnsrapporter?',
    answer:
      'Absolutt! Du kan laste ned alle vaktene dine som en PDF eller Excel-fil (CSV) når som helst. Perfekt når du skal levere timelistene til arbeidsgiveren eller bare vil ha oversikt over måneden.\n\nRapporten viser alle detaljene: arbeidstimer, pauser, tillegg og totallønn for hver vakt.',
  },
  {
    question: 'Hva koster det? Er det gratis?',
    answer:
      'Ja, det er helt gratis å starte! Du kan bruke kalkulatoren så mye du vil, men du har kun plass til vakter for én måned om gangen. Det holder for de fleste.\n\nTrenger du mer? Vi har Pro-abonnementet som gir deg ubegrenset antall måneder. Det koster bare 29 kr i måneden – mindre enn en kopp kaffe i uka!',
  },
  {
    question: 'Kan jeg bruke den på mobil som en app?',
    answer:
      'Ja! Du kan installere kalkulatoren som en app på telefonen din. Bare besøk nettsiden i Safari eller Chrome, så er det mulig å «legge til på hjemskjerm».\n\nDen fungerer som en vanlig app da – med eget ikon og alt. Du trenger internett for å synke data, men de fleste funksjonene virker selv om nettet er tregt.',
  },
  {
    question: 'Er dataene mine trygge?',
    answer:
      'Selvfølgelig! Vi er supernøye med personvern. Dataene dine (som vakter og timelønn) sendes bare til serveren når du velger å logge inn – aldri ellers.\n\n Vi lagrer bare det som trengs for at kalkulatoren skal virke: vaktene dine, innstillingene og profilbildet. Ingenting mer!',
  },
] as const;

export default function LandingPage() {
  return (
    <main className="relative min-h-screen overflow-hidden bg-background text-text-primary">
      <ViewportHeightSetter />
      <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
        <div
          className="absolute -top-40 left-1/2 h-[420px] w-[420px] -translate-x-1/2 rounded-full blur-[140px]"
          style={{ backgroundColor: 'hsla(var(--brand-gradientStart) / 0.18)' }}
        />
        <div
          className="absolute bottom-0 right-0 h-[360px] w-[360px] translate-x-1/3 translate-y-1/3 rounded-full blur-[120px]"
          style={{ backgroundColor: 'hsla(var(--brand-gradientEnd) / 0.12)' }}
        />
      </div>

      <section className="relative flex min-h-[calc(var(--hero-initial-dvh,100dvh))] w-full items-center justify-center pb-[calc(5rem+env(safe-area-inset-bottom))] pt-8 sm:pb-[calc(6rem+env(safe-area-inset-bottom))] sm:pt-12 lg:pb-[calc(7rem+env(safe-area-inset-bottom))]">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,hsla(var(--brand-gradientStart)/0.16),transparent_55%)]" />
        <div className="relative w-full max-w-4xl px-6 sm:px-0">
          <div className="relative mx-auto flex w-full max-w-[32rem] flex-col items-center gap-8 overflow-hidden rounded-[44px] border border-border-subtle/60 bg-surface-primary/70 px-6 pb-[calc(3rem+env(safe-area-inset-bottom))] pt-12 shadow-app max-h-[760px] sm:max-w-xl sm:max-h-[820px] sm:px-12">
            <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,hsla(var(--brand-gradientStart)/0.16),transparent_55%)]" />
            <div className="relative flex flex-col items-center gap-8 text-center">
              <span className="inline-flex items-center gap-2 rounded-full border border-border-subtle/50 bg-surface-secondary/40 px-5 py-2 text-sm text-text-secondary">
                kkarlsen_06 • DEV
              </span>
              <div className="space-y-6">
                <h1 className="text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
                  Få kontroll over lønnen din
                </h1>
                <p className="text-pretty text-base text-text-secondary sm:text-lg">
                  Lønnskalkulatoren som tar vakter, tillegg og tariff på alvor. Excel er over.
                </p>
              </div>
              <div className="mx-auto grid w-full max-w-sm grid-cols-2 gap-3 sm:max-w-none sm:grid-cols-4 sm:justify-items-center">
                {heroHighlights.map((highlight) => (
                  <span
                    key={highlight}
                    className="inline-flex h-10 w-full items-center justify-center gap-2 rounded-full border border-border-subtle/40 bg-background/60 px-4 text-sm font-medium text-text-secondary sm:h-11 sm:w-[9rem]"
                  >
                    {highlight}
                  </span>
                ))}
              </div>
              <div className="flex w-full flex-col gap-3 sm:flex-row sm:items-center sm:justify-center">
                <Button
                  asChild
                  className="h-12 w-full rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-8 text-base font-semibold text-text-inverse shadow-app-lg sm:w-auto"
                >
                  <Link href="https://app.kkarlsen.dev" target="_blank" rel="noopener noreferrer">
                    Åpne appen
                  </Link>
                </Button>
                <Button
                  asChild
                  variant="outline"
                  className="h-12 w-full rounded-full border-border-subtle bg-surface-primary/40 px-8 text-base font-semibold text-text-primary hover:border-brand-gradientMid hover:text-text-primary sm:w-auto"
                >
                  <Link href="#faq">FAQ</Link>
                </Button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section
        id="features"
        className="px-6 pb-20 sm:pb-24 lg:pb-28"
      >
        <div className="mx-auto w-full max-w-4xl space-y-8">
          <div className="space-y-4">
            <p className="text-sm font-medium uppercase tracking-[0.32em] text-text-muted">
              Hvorfor kkarlsen.dev?
            </p>
            <h2 className="text-pretty text-3xl font-semibold sm:text-4xl">
              Laget for deg som vil ha full kontroll
            </h2>
            <p className="max-w-2xl text-pretty text-base text-text-secondary sm:text-lg">
              Våre viktigste funksjoner er designet for å gjøre lønnsberegningen enkel, nøyaktig og pålitelig.
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {features.map(({ icon: Icon, title, description }) => (
              <div
                key={title}
                className="group flex h-full flex-col gap-4 rounded-[32px] border border-border-subtle/60 bg-surface-primary/80 p-6 shadow-app transition-all duration-200 hover:-translate-y-1 hover:border-brand-gradientMid/60 hover:shadow-app-lg"
              >
                <span
                  className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-brand-gradientStart/20 via-brand-gradientMid/15 to-brand-gradientEnd/20 text-brand-gradientStart shadow-inner"
                  style={{ boxShadow: 'inset 0 1px 0 hsl(var(--brand-gradientEnd) / 0.2)' }}
                >
                  <Icon className="h-5 w-5" />
                </span>
                <div className="space-y-3">
                  <h3 className="text-lg font-semibold text-text-primary">{title}</h3>
                  <p className="text-sm text-text-secondary">{description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section
        id="faq"
        className="px-6 pb-20 sm:pb-28 lg:pb-32"
      >
        <div className="mx-auto w-full max-w-3xl rounded-[40px] border border-border-subtle/70 bg-surface-primary/80 p-8 shadow-app-lg sm:p-12">
          <div className="mb-10 space-y-4 text-center">
            <p className="text-sm font-medium uppercase tracking-[0.32em] text-text-muted">FAQ</p>
            <h2 className="text-3xl font-semibold sm:text-4xl">Vanlige spørsmål</h2>
            <p className="text-base text-text-secondary">
              Alt du trenger å vite om vakter, rapporter og hvordan dataene dine behandles.
            </p>
          </div>

          <Accordion type="single" collapsible className="space-y-2">
            {faqs.map((faq) => (
              <AccordionItem key={faq.question} value={faq.question} className="overflow-hidden">
                <AccordionTrigger className="rounded-2xl px-4 text-left text-base sm:text-lg">
                  {faq.question}
                </AccordionTrigger>
                <AccordionContent className="px-4">
                  {faq.answer.split('\n\n').map((paragraph) => (
                    <p key={paragraph} className="pb-4 text-base text-text-secondary last:pb-1">
                      {paragraph}
                    </p>
                  ))}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>
      </section>

      <section className="px-6 pb-16 sm:pb-24">
        <div className="mx-auto flex w-full max-w-3xl flex-col items-center gap-6 rounded-[40px] border border-border-subtle/60 bg-surface-secondary/30 px-8 py-10 text-center shadow-app">
          <h2 className="text-3xl font-semibold sm:text-[2.5rem]">Klar for å teste vaktene dine?</h2>
          <p className="max-w-xl text-pretty text-base text-text-secondary sm:text-lg">
            Opprett en konto gratis og få kontroll på tillegg, overtid og rapporter før neste
            lønning går ut.
          </p>
          <Button
            asChild
            className="h-12 rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-10 text-base font-semibold text-text-inverse shadow-app-lg"
          >
            <Link href="https://app.kkarlsen.dev" target="_blank" rel="noopener noreferrer">
              Start nå – gratis
            </Link>
          </Button>
        </div>
      </section>

      <section className="px-6 pb-16 sm:pb-20">
        <div className="mx-auto flex w-full max-w-3xl flex-col items-center gap-6 rounded-[40px] border border-border-subtle/60 bg-surface-primary/80 px-8 py-10 text-center shadow-app">
          <h2 className="text-2xl font-semibold sm:text-3xl">Har du spørsmål?</h2>
          <p className="max-w-xl text-pretty text-base text-text-secondary">
            Ta kontakt hvis du lurer på noe eller har tilbakemeldinger.
          </p>
          <Button
            asChild
            variant="outline"
            className="h-12 rounded-full border-border-subtle bg-surface-primary px-10 text-base font-semibold text-text-primary hover:border-brand-gradientMid hover:text-text-primary"
          >
            <a href="mailto:kkarlsen06@kkarlsen.dev?subject=Kontakt%20fra%20kkarlsen.dev&body=Hei%2C%20Hjalmar!%0A%0AJeg%20lurte%20p%C3%A5%20">
              Ta kontakt
            </a>
          </Button>
        </div>
      </section>

      <footer className="px-6 pb-10">
        <div className="mx-auto w-full max-w-6xl space-y-2 text-center">
          <div className="flex items-center justify-center gap-3 text-sm">
            <Link href="/privacy" className="text-text-secondary hover:text-text-primary transition-colors">
              Personvernerklæring
            </Link>
            <span className="text-text-muted">•</span>
            <Link href="/terms" className="text-text-secondary hover:text-text-primary transition-colors">
              Vilkår for bruk
            </Link>
          </div>
          <div className="text-sm text-text-secondary">
            © 2025 Hjalmar Kristensen-Karlsen
          </div>
        </div>
      </footer>
    </main>
  );
}
