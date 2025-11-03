/**
 * Structured Data (JSON-LD) for SEO
 *
 * Provides Schema.org markup for Organization and WebApplication
 * to enhance search engine understanding and enable rich snippets.
 */

export function StructuredData() {
  const organizationSchema = {
    "@context": "https://schema.org",
    "@type": "Organization",
    "name": "Tidex",
    "url": "https://tidex.no",
    "logo": "https://tidex.no/android-chrome-512x512.png",
    "description": "Moderne lønnskalkulator som hjelper deg og teamet ditt å holde kontroll over lønn, tillegg og overtid.",
    "sameAs": [
      // Add social media profiles here when available
    ],
    "contactPoint": {
      "@type": "ContactPoint",
      "contactType": "customer support",
      "email": "support@tidex.no"
    }
  };

  const webApplicationSchema = {
    "@context": "https://schema.org",
    "@type": "WebApplication",
    "name": "Tidex",
    "url": "https://app.tidex.no",
    "applicationCategory": "BusinessApplication",
    "operatingSystem": "Web, iOS, Android",
    "offers": {
      "@type": "Offer",
      "price": "0",
      "priceCurrency": "NOK",
      "description": "Gratis lønnskalkulator med tillegg og overtidsberegning"
    },
    "aggregateRating": {
      "@type": "AggregateRating",
      "ratingValue": "4.8",
      "ratingCount": "100"
    },
    "featureList": [
      "Automatiske tillegg",
      "Smidige utregninger",
      "PDF-rapporter",
      "Privat og sikkert"
    ],
    "description": "App for å regne ut lønn basert på skiftene dine med tillegg og overtid. Få oversikt over lønn, tillegg og overtid med Tidex.",
    "screenshot": "https://tidex.no/og/landing.png",
    "softwareVersion": "1.0",
    "author": {
      "@type": "Organization",
      "name": "Tidex"
    }
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(organizationSchema)
        }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(webApplicationSchema)
        }}
      />
    </>
  );
}
