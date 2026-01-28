"use client";

/**
 * Wagey Showcase Component
 *
 * Marketing-style page shown to free users who don't have Wagey access.
 * Highlights Wagey's capabilities and encourages upgrading to Pro/Max.
 */

import Link from "next/link";
import { MessageSquare, Zap, Calculator, Calendar, Sparkles, ArrowRight, Play } from "lucide-react";
import { Button } from "@/components/app/Button";
import { Card } from "@/components/app/Card";
import { useTranslations } from "@/lib/i18n/client";

const features = [
  { icon: MessageSquare, key: "naturalLanguage" },
  { icon: Zap, key: "quickActions" },
  { icon: Calculator, key: "wageCalculations" },
  { icon: Calendar, key: "scheduling" },
] as const;

const exampleConversations = [
  { role: "user", messageKey: "example1User" },
  { role: "tool", toolKey: "example1Tool" },
  { role: "assistant", messageKey: "example1Assistant" },
  { role: "user", messageKey: "example2User" },
  { role: "tool", toolKey: "example2Tool" },
  { role: "assistant", messageKey: "example2Assistant" },
] as const;

type WageyShowcaseProps = {
  onTryWagey?: () => void;
};

export function WageyShowcase({ onTryWagey }: WageyShowcaseProps) {
  const { t, locale } = useTranslations();
  const showcase = t.pages.wagey.showcase;

  return (
    <main className="relative min-h-screen overflow-hidden bg-background text-text-primary pb-[calc(5rem+env(safe-area-inset-bottom))]">
      {/* Background gradients */}
      <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
        <div
          className="absolute -top-40 left-1/2 h-105 w-105 -translate-x-1/2 rounded-full blur-[140px]"
          style={{ backgroundColor: "hsla(var(--brand-gradientStart) / 0.18)" }}
        />
        <div
          className="absolute bottom-0 right-0 h-90 w-90 translate-x-1/3 translate-y-1/3 rounded-full blur-[120px]"
          style={{ backgroundColor: "hsla(var(--brand-gradientEnd) / 0.12)" }}
        />
      </div>

      {/* Hero Section */}
      <section className="relative px-6 pt-12 pb-16 sm:pt-16 sm:pb-20">
        <div className="mx-auto w-full max-w-3xl text-center">
          <div className="mb-6 flex justify-center">
            <div className="relative">
              <div
                className="pointer-events-none absolute inset-0 -z-10 blur-[60px] opacity-60"
                style={{
                  background:
                    "radial-gradient(circle, hsla(var(--brand-gradientStart) / 0.4), hsla(var(--brand-gradientEnd) / 0.3))",
                }}
              />
              <div className="flex h-20 w-20 items-center justify-center rounded-3xl bg-linear-to-br from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end shadow-app-lg">
                <Sparkles className="h-10 w-10 text-white" />
              </div>
            </div>
          </div>

          <h1 className="mb-4 text-balance text-4xl font-bold tracking-tight sm:text-5xl">
            {showcase.hero.title}
          </h1>
          <p className="mb-2 text-xl text-text-secondary font-medium">
            {showcase.hero.subtitle}
          </p>
          <p className="mx-auto max-w-xl text-pretty text-base text-text-muted sm:text-lg">
            {showcase.hero.description}
          </p>

          {/* Try Wagey Button */}
          {onTryWagey && (
            <Button
              onClick={onTryWagey}
              className="mt-8 h-12 rounded-full bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end px-8 text-base font-semibold text-text-inverse shadow-app-lg"
            >
              <Play className="mr-2 h-4 w-4" />
              {showcase.hero.tryButton}
            </Button>
          )}
        </div>
      </section>

      {/* Features Grid */}
      <section className="px-6 pb-16 sm:pb-20">
        <div className="mx-auto w-full max-w-4xl">
          <h2 className="mb-8 text-center text-2xl font-semibold sm:text-3xl">
            {showcase.features.title}
          </h2>

          <div className="grid gap-4 sm:grid-cols-2">
            {features.map(({ icon: Icon, key }) => {
              const feature = showcase.features.items[key];
              return (
                <div
                  key={key}
                  className="group flex flex-col gap-4 rounded-card border border-border-subtle/60 bg-surface-primary/80 p-6 shadow-app transition-all duration-200 hover:-translate-y-1 hover:border-brand-gradient-mid/60 hover:shadow-app-lg"
                >
                  <span
                    className="flex h-12 w-12 items-center justify-center rounded-2xl bg-linear-to-br from-brand-gradient-start/20 via-brand-gradient-mid/15 to-brand-gradient-end/20 text-brand-gradient-start shadow-inner"
                    style={{
                      boxShadow: "inset 0 1px 0 hsl(var(--brand-gradientEnd) / 0.2)",
                    }}
                  >
                    <Icon className="h-5 w-5" />
                  </span>
                  <div className="space-y-2">
                    <h3 className="text-lg font-semibold text-text-primary">
                      {feature.title}
                    </h3>
                    <p className="text-sm text-text-secondary">{feature.description}</p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* Example Conversations */}
      <section className="px-6 pb-16 sm:pb-20">
        <div className="mx-auto w-full max-w-2xl">
          <h2 className="mb-8 text-center text-2xl font-semibold sm:text-3xl">
            {showcase.examples.title}
          </h2>

          <div className="rounded-4xl border border-border-subtle/60 bg-surface-primary/70 p-6 shadow-app-lg sm:p-8">
            <div className="space-y-4">
              {exampleConversations.map((item, index) => {
                if (item.role === "user") {
                  const message = showcase.examples[item.messageKey];
                  return (
                    <div key={index} className="flex flex-col gap-2">
                      <div className="flex justify-end">
                        <Card className="max-w-[85%] rounded-3xl shadow-app bg-linear-to-br from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end text-white backdrop-blur">
                          <div className="p-3 md:p-4 flex flex-col gap-1">
                            <div className="text-[11px] font-semibold text-white/90 whitespace-nowrap">
                              {showcase.examples.you}
                            </div>
                            <div className="whitespace-pre-wrap text-sm md:text-base leading-relaxed">
                              {message}
                            </div>
                          </div>
                        </Card>
                      </div>
                    </div>
                  );
                }

                if (item.role === "tool") {
                  const toolMessage = showcase.examples[item.toolKey];
                  return (
                    <div key={index} className="flex flex-col gap-2">
                      <div className="flex justify-start">
                        <Card className="max-w-[85%] rounded-3xl shadow-app-sm bg-surface-secondary/90 text-text-muted border border-border/60 backdrop-blur">
                          <div className="p-3 md:p-4 flex flex-col gap-1">
                            <div className="text-[11px] font-semibold text-text-muted/70 whitespace-nowrap">
                              {showcase.examples.wagey} • <span className="text-brand-gradient-mid">{t.pages.wagey.worked}</span>
                            </div>
                            <div className="whitespace-pre-wrap text-sm md:text-base leading-relaxed flex items-center gap-2">
                              <span className="text-green-500">✓</span> {toolMessage}
                            </div>
                          </div>
                        </Card>
                      </div>
                    </div>
                  );
                }

                // Assistant message
                const message = showcase.examples[item.messageKey];
                return (
                  <div key={index} className="flex flex-col gap-2">
                    <div className="flex justify-start">
                      <Card className="max-w-[85%] rounded-3xl shadow-app-sm bg-surface-secondary/90 text-text-primary border border-border/60 backdrop-blur">
                        <div className="p-3 md:p-4 flex flex-col gap-1">
                          <div className="text-[11px] font-semibold text-text-muted/70 whitespace-nowrap">
                            {showcase.examples.wagey}
                          </div>
                          <div className="whitespace-pre-wrap text-sm md:text-base leading-relaxed">
                            {message}
                          </div>
                        </div>
                      </Card>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Pricing Comparison */}
      <section className="px-6 pb-16 sm:pb-20">
        <div className="mx-auto w-full max-w-3xl">
          <h2 className="mb-8 text-center text-2xl font-semibold sm:text-3xl">
            {showcase.pricing.title}
          </h2>

          <div className="grid gap-4 sm:grid-cols-2">
            {/* Pro Plan */}
            <div className="rounded-card border border-border-subtle/60 bg-surface-primary/80 p-6 shadow-app">
              <div className="mb-4">
                <h3 className="text-xl font-bold text-text-primary">Pro</h3>
                <p className="text-sm text-text-secondary">
                  {showcase.pricing.proMessages}
                </p>
              </div>
              <ul className="space-y-2 text-sm text-text-secondary">
                <li className="flex items-center gap-2">
                  <span className="text-brand-gradient-start">✓</span>
                  {showcase.pricing.features.shifts}
                </li>
                <li className="flex items-center gap-2">
                  <span className="text-brand-gradient-start">✓</span>
                  {showcase.pricing.features.calculations}
                </li>
                <li className="flex items-center gap-2">
                  <span className="text-brand-gradient-start">✓</span>
                  {showcase.pricing.features.scheduling}
                </li>
              </ul>
            </div>

            {/* Max Plan */}
            <div className="relative rounded-card border-2 border-brand-gradient-mid/60 bg-surface-primary/80 p-6 shadow-app-lg">
              <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                <span className="rounded-full bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end px-4 py-1 text-xs font-semibold text-text-inverse">
                  {showcase.pricing.recommended}
                </span>
              </div>
              <div className="mb-4">
                <h3 className="text-xl font-bold text-text-primary">Max</h3>
                <p className="text-sm text-text-secondary">
                  {showcase.pricing.maxMessages}
                </p>
              </div>
              <ul className="space-y-2 text-sm text-text-secondary">
                <li className="flex items-center gap-2">
                  <span className="text-brand-gradient-start">✓</span>
                  {showcase.pricing.features.allPro}
                </li>
                <li className="flex items-center gap-2">
                  <span className="text-brand-gradient-start">✓</span>
                  {showcase.pricing.features.moreMessages}
                </li>
                <li className="flex items-center gap-2">
                  <span className="text-brand-gradient-start">✓</span>
                  {showcase.pricing.features.priority}
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="px-6 pb-16">
        <div className="mx-auto flex w-full max-w-2xl flex-col items-center gap-6 rounded-[40px] border border-border-subtle/60 bg-surface-secondary/30 px-8 py-10 text-center shadow-app">
          <h2 className="text-2xl font-semibold sm:text-3xl">{showcase.cta.title}</h2>
          <p className="max-w-md text-pretty text-base text-text-secondary">
            {showcase.cta.description}
          </p>
          <Button
            asChild
            className="h-12 rounded-full bg-linear-to-r from-brand-gradient-start via-brand-gradient-mid to-brand-gradient-end px-8 text-base font-semibold text-text-inverse shadow-app-lg"
          >
            <Link href={`/${locale}/settings/subscription`}>
              {showcase.cta.button}
              <ArrowRight className="ml-2 h-4 w-4" />
            </Link>
          </Button>
        </div>
      </section>
    </main>
  );
}
