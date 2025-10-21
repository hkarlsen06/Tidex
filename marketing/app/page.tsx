import Link from "next/link"
import Image from "next/image"
import { Button } from "@/components/ui/button"
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion"
import { FileText, Zap, Shield, Layers } from "lucide-react"

export default function LandingPage() {
  return (
    <div className="relative min-h-screen overflow-hidden">
      {/* Animated background orbs */}
      <div className="fixed inset-0 -z-10 pointer-events-none" aria-hidden="true">
        <div className="orb-1 absolute -top-[220px] -left-[220px] w-[600px] h-[600px] rounded-full bg-primary/50 blur-[140px] opacity-[0.08]" />
        <div className="orb-2 absolute -bottom-[320px] -right-[320px] w-[800px] h-[800px] rounded-full bg-secondary/50 blur-[140px] opacity-[0.08]" />
        <div className="orb-3 absolute top-[40%] left-[55%] w-[500px] h-[500px] rounded-full bg-accent/50 blur-[140px] opacity-[0.08]" />
      </div>

      {/* Navbar */}
      <nav className="fixed top-0 left-0 right-0 z-50 border-b border-border bg-background/90 backdrop-blur-lg" role="navigation" aria-label="Toppnavigasjon">
        <div className="container mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex h-16 items-center justify-center">
            <Link
              href="https://github.com/kkarlsen06"
              target="_blank"
              rel="noopener noreferrer"
              className="text-xl font-extrabold bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent hover:opacity-80 transition-opacity"
              aria-label="Åpne GitHub-profil i ny fane"
            >
              kkarlsen_06 • DEV
            </Link>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <main id="main" className="relative pt-24 pb-12 px-4 sm:px-6 lg:px-8">
        {/* Background title animation */}
        <div className="absolute inset-0 -z-10 overflow-hidden pointer-events-none" aria-hidden="true">
          <div className="absolute top-[-20vh] left-1/2 -translate-x-1/2 -rotate-[18deg]">
            <div className="flex flex-col items-center gap-[clamp(80px,18vh,240px)] animate-[bg-scroll-up_120s_linear_infinite]">
              {/* First sequence */}
              <div className="flex flex-col items-center gap-[clamp(80px,18vh,240px)]">
                {[...Array(6)].map((_, i) => (
                  <span
                    key={`word-1-${i}`}
                    className="font-black text-[clamp(12rem,38vmin,72rem)] leading-[0.9] tracking-[-0.03em] text-foreground opacity-[0.06] brightness-[0.65] saturate-[0.8] contrast-[0.9] blur-[0.4px] whitespace-nowrap"
                  >
                    Lønnskalkulator
                  </span>
                ))}
              </div>
              {/* Second sequence for seamless loop */}
              <div className="flex flex-col items-center gap-[clamp(80px,18vh,240px)]">
                {[...Array(6)].map((_, i) => (
                  <span
                    key={`word-2-${i}`}
                    className="font-black text-[clamp(12rem,38vmin,72rem)] leading-[0.9] tracking-[-0.03em] text-foreground opacity-[0.06] brightness-[0.65] saturate-[0.8] contrast-[0.9] blur-[0.4px] whitespace-nowrap"
                  >
                    Lønnskalkulator
                  </span>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Hero content */}
        <div className="container mx-auto max-w-[560px] relative z-10">
          <section className="glass-card rounded-[40px] border border-border p-6 sm:p-8 text-center shadow-lg" aria-label="Åpne applikasjonen">
            {/* Title */}
            <h1 className="text-4xl sm:text-5xl font-extrabold tracking-tight mb-6 leading-tight">
              Få kontroll <br />
              over lønnen din
            </h1>

            {/* Decorative line */}
            <div className="mx-auto w-14 h-[1px] bg-gradient-to-r from-primary to-secondary opacity-25 rounded-full mb-6" />

            {/* Tagline */}
            <p className="text-lg sm:text-xl text-muted-foreground mb-6 max-w-[50ch] mx-auto">
              Lønnskalkulatoren som tar vakter,<br className="hidden sm:inline" /> tillegg og tariff på alvor. Excel er over.
            </p>

            {/* Feature chips */}
            <div className="grid grid-cols-2 gap-3 mb-8" aria-hidden="true">
              <div className="flex items-center justify-center gap-2 bg-white/[0.05] border border-border rounded-full px-4 py-2 backdrop-blur-sm animate-chip-float">
                <FileText className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm text-muted-foreground">Nøyaktig</span>
              </div>
              <div className="flex items-center justify-center gap-2 bg-white/[0.05] border border-border rounded-full px-4 py-2 backdrop-blur-sm animate-chip-float [animation-delay:0.6s]">
                <Zap className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm text-muted-foreground">Rask</span>
              </div>
              <div className="flex items-center justify-center gap-2 bg-white/[0.05] border border-border rounded-full px-4 py-2 backdrop-blur-sm animate-chip-float [animation-delay:1.2s]">
                <Shield className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm text-muted-foreground">Privat</span>
              </div>
              <div className="flex items-center justify-center gap-2 bg-white/[0.05] border border-border rounded-full px-4 py-2 backdrop-blur-sm animate-chip-float [animation-delay:1.8s]">
                <Layers className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm text-muted-foreground">Stabil</span>
              </div>
            </div>

            {/* CTA buttons */}
            <div className="flex flex-col gap-3">
              <Button asChild size="xl" className="w-full">
                <Link href="https://app.kkarlsen.dev" aria-label="Åpne kalkulatoren nå">
                  Åpne appen
                </Link>
              </Button>
              <Button asChild size="xl" variant="secondary" className="w-full">
                <Link href="#demo">
                  Se demo (30 sek)
                </Link>
              </Button>
            </div>
          </section>
        </div>
      </main>

      {/* Demo Section */}
      <section id="demo" className="py-16 px-4 sm:px-6 lg:px-8">
        <div className="container mx-auto max-w-6xl text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-8 tracking-tight">
            Se hvor enkelt det er
          </h2>
          <div className="relative rounded-[40px] border border-border overflow-hidden shadow-xl">
            <Image
              src="/demo.gif"
              alt="Demo av lønnskalkulatoren"
              width={800}
              height={450}
              className="w-full h-auto"
              priority
            />
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section id="faq" className="py-16 px-4 sm:px-6 lg:px-8" aria-labelledby="faq-heading">
        <div className="container mx-auto max-w-[880px]">
          <div className="glass-card rounded-[24px] border border-border p-8 sm:p-12 backdrop-blur-xl">
            <h2 id="faq-heading" className="text-3xl sm:text-4xl font-bold text-center mb-12 tracking-tight">
              Vanlige spørsmål
            </h2>

            <div className="mx-auto w-12 h-[2px] bg-gradient-to-r from-primary to-secondary opacity-60 rounded-full mb-12" />

            <Accordion type="single" collapsible className="w-full">
              <AccordionItem value="item-1">
                <AccordionTrigger>Hvordan håndteres pauser og pausetrekk?</AccordionTrigger>
                <AccordionContent>
                  Vi regner ut lønna di smart! Hvis du jobber over 5,5 timer, trekker vi automatisk 30 minutter for pause, akkurat som de fleste arbeidsgivere gjør. Du kan også legge inn dine egne pauser manuelt.
                  <br /><br />
                  Jobber du nattskift eller lange vakter? Ingen problem! Kalkulatoren takler alt fra vanlige arbeidsdager til skift som går over midnatt. Du kan også justere pausereglene i innstillingene hvis arbeidsplassen din har andre regler.
                </AccordionContent>
              </AccordionItem>

              <AccordionItem value="item-2">
                <AccordionTrigger>Hvordan fungerer overtid og tillegg?</AccordionTrigger>
                <AccordionContent>
                  Du forteller oss hvilke tillegg du har rett på, så regner vi ut alt automatisk! Har du kveldstillegg fra 18:00? Helgetillegg på lørdager og søndager? Bare sett opp reglene én gang i innstillingene.
                  <br /><br />
                  Når du registrerer en vakt, ser kalkulatoren på tidspunktet og dagen, og legger til riktige tillegg oppå grunnlønna di. Enkelt og greit – ingen Excel-formler å tenke på!
                </AccordionContent>
              </AccordionItem>

              <AccordionItem value="item-3">
                <AccordionTrigger>Hvor lagres dataene mine?</AccordionTrigger>
                <AccordionContent>
                  Trygt og smart! Alle innstillingene dine (som timelønn og pauseregler) lagres lokalt på telefonen eller PC-en din, så appen starter lynraskt hver gang.
                  <br /><br />
                  Når du logger inn, synkroniserer vi også vaktene og innstillingene dine til skyen. Da kan du bytte mellom telefon og PC, og alt er tilgjengelig overalt. Ingen data forsvinner!
                </AccordionContent>
              </AccordionItem>

              <AccordionItem value="item-4">
                <AccordionTrigger>Kan jeg laste ned lønnsrapporter?</AccordionTrigger>
                <AccordionContent>
                  Absolutt! Du kan laste ned alle vaktene dine som en Excel-fil (CSV) når som helst. Perfekt når du skal levere timelistene til arbeidsgiveren eller bare vil ha oversikt over måneden.
                  <br /><br />
                  Rapporten viser alle detaljene: arbeidstimer, pauser, tillegg og totallønn for hver vakt. Med gratisversjonen kan du ha vakter for én måned – sletter du gamle måneder, kan du fortsette gratis så lenge du vil!
                </AccordionContent>
              </AccordionItem>

              <AccordionItem value="item-5">
                <AccordionTrigger>Hva koster det? Er det gratis?</AccordionTrigger>
                <AccordionContent>
                  Ja, det er helt gratis å starte! Du kan bruke kalkulatoren så mye du vil, men du har kun plass til vakter for én måned om gangen. Det holder for de fleste.
                  <br /><br />
                  Trenger du mer? Vi har Pro-abonnementet som gir deg ubegrenset antall måneder. I tillegg har vi et Enterprise-abonnement for bedrifter som vil administrere flere ansatte og få avanserte rapporter. Du kan oppgradere direkte fra appen når du trenger det.
                </AccordionContent>
              </AccordionItem>

              <AccordionItem value="item-6">
                <AccordionTrigger>Kan jeg bruke den på mobil som en app?</AccordionTrigger>
                <AccordionContent>
                  Ja! Du kan installere kalkulatoren som en ekte app på telefonen din. Bare besøk nettsiden i Safari eller Chrome, så får du tilbud om å &quot;legge til på hjemskjerm&quot;.
                  <br /><br />
                  Den fungerer som en vanlig app da – med eget ikon og alt. Du trenger internett for å synke data, men de fleste funksjonene virker selv om nettet er tregt.
                </AccordionContent>
              </AccordionItem>

              <AccordionItem value="item-7">
                <AccordionTrigger>Er dataene mine trygge?</AccordionTrigger>
                <AccordionContent>
                  Selvfølgelig! Vi er supernøye med personvern. Dataene dine (som vakter og timelønn) sendes bare til serveren når du velger å logge inn – aldri ellers.
                  <br /><br />
                  Alt er kryptert og beskyttet, akkurat som nettbank. Vi lagrer bare det som trengs for at kalkulatoren skal virke: vaktene dine, innstillingene og profilbildet. Ingenting mer!
                </AccordionContent>
              </AccordionItem>
            </Accordion>

            <div className="mt-12 text-center p-6 bg-white/[0.05] border border-white/10 rounded-[40px]">
              <p className="text-lg text-muted-foreground">
                Klar til å ta kontroll over lønna di?{" "}
                <Link href="https://app.kkarlsen.dev" className="text-primary font-semibold hover:text-primary/80 transition-colors">
                  Start gratis nå!
                </Link>
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="mt-16 border-t border-border py-8 px-4 sm:px-6 lg:px-8">
        <div className="container mx-auto">
          <div className="flex flex-col items-center gap-4 text-center">
            <p className="text-sm text-muted-foreground">
              &copy; 2025 Hjalmar Kristensen-Karlsen
            </p>
          </div>
        </div>
      </footer>
    </div>
  )
}
