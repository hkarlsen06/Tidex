import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Tidex – Support",
  description:
    "Get help with Tidex, the work shift and earnings tracker app. Contact support for questions about the app, subscriptions, billing, or your account.",
  openGraph: {
    title: "Tidex – Support",
    description:
      "Get help with Tidex, the work shift and earnings tracker app. Contact support for questions about the app, subscriptions, billing, or your account.",
    url: "https://app.tidex.no/support",
    type: "website",
  },
};

export default function SupportPage() {
  const currentYear = new Date().getFullYear();

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto max-w-3xl px-4 py-12">
        {/* Header */}
        <header className="mb-12 text-center">
          <h1 className="text-3xl font-bold text-text-primary mb-4">
            Tidex – Support
          </h1>
          <p className="text-text-secondary text-lg max-w-2xl mx-auto">
            Tidex helps you track work shifts and earnings. If you need help
            with the app, subscriptions, or your account, contact us using the
            information below.
          </p>
        </header>

        {/* Contact Section */}
        <section className="mb-12">
          <h2 className="text-xl font-semibold text-text-primary mb-4">
            Contact Us
          </h2>
          <div className="bg-surface-secondary rounded-lg p-6 border border-border-subtle">
            <p className="text-text-secondary mb-4">
              For questions, issues, or feedback about Tidex, reach out to our
              support team.
            </p>
            <p className="text-text-primary mb-6">
              Email:{" "}
              <a
                href="mailto:contact@tidex.no"
                className="text-blue-500 hover:text-blue-400 underline"
              >
                contact@tidex.no
              </a>
            </p>
            <a
              href="mailto:contact@tidex.no"
              className="inline-flex items-center justify-center px-6 py-3 text-base font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors"
            >
              Contact Support
            </a>
          </div>
        </section>

        {/* Subscriptions & Billing Section */}
        <section className="mb-12">
          <h2 className="text-xl font-semibold text-text-primary mb-4">
            Subscriptions & Billing
          </h2>
          <div className="bg-surface-secondary rounded-lg p-6 border border-border-subtle">
            <p className="text-text-secondary mb-4">
              If you have questions about subscriptions, billing, renewals, or
              cancellations:
            </p>
            <ul className="list-disc list-inside text-text-secondary space-y-2 mb-4">
              <li>
                iOS subscriptions are managed through Apple App Store
                subscriptions.
              </li>
              <li>Web subscriptions are managed through Tidex.</li>
            </ul>
            <p className="text-text-secondary">
              If you believe you were charged incorrectly or need help with
              billing, contact support at{" "}
              <a
                href="mailto:contact@tidex.no"
                className="text-blue-500 hover:text-blue-400 underline"
              >
                contact@tidex.no
              </a>
              .
            </p>
          </div>
        </section>

        {/* FAQ Section */}
        <section className="mb-12">
          <h2 className="text-xl font-semibold text-text-primary mb-4">
            Frequently Asked Questions
          </h2>
          <div className="space-y-4">
            <div className="bg-surface-secondary rounded-lg p-6 border border-border-subtle">
              <h3 className="font-medium text-text-primary mb-2">
                How do I cancel my subscription?
              </h3>
              <p className="text-text-secondary">
                iOS subscriptions can be managed through your Apple ID
                subscription settings. Go to Settings &gt; [Your Name] &gt;
                Subscriptions on your iPhone or iPad to manage or cancel your
                subscription.
              </p>
            </div>
            <div className="bg-surface-secondary rounded-lg p-6 border border-border-subtle">
              <h3 className="font-medium text-text-primary mb-2">
                How do I delete my account?
              </h3>
              <p className="text-text-secondary">
                To delete your Tidex account and all associated data, contact
                support at{" "}
                <a
                  href="mailto:contact@tidex.no"
                  className="text-blue-500 hover:text-blue-400 underline"
                >
                  contact@tidex.no
                </a>{" "}
                with your request. We will process account deletions within 30
                days.
              </p>
            </div>
          </div>
        </section>

        {/* Footer */}
        <footer className="border-t border-border-subtle pt-8">
          <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
            <p className="text-sm text-text-muted">
              &copy; {currentYear} Tidex. All rights reserved.
            </p>
            <div className="flex gap-6">
              <Link
                href="https://tidex.no/privacy"
                className="text-sm text-text-secondary hover:text-text-primary transition-colors"
              >
                Privacy Policy
              </Link>
              <Link
                href="https://tidex.no/terms"
                className="text-sm text-text-secondary hover:text-text-primary transition-colors"
              >
                Terms of Service
              </Link>
            </div>
          </div>
        </footer>
      </div>
    </div>
  );
}
