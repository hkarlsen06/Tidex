// Redirect helper for marketing → app CTA
// Picks APP_URL from env in dev/prod, then wires all [data-open-app] elements.

const APP_URL = (import.meta?.env && import.meta.env.VITE_APP_URL)
  || ((location.hostname === 'localhost' || location.hostname === '127.0.0.1')
      ? 'http://localhost:5173'
      : 'https://kalkulator.kkarlsen.dev');

function wireOpenApp(selector = '[data-open-app]') {
  const els = document.querySelectorAll(selector);
  if (!els.length) return;

  els.forEach((el) => {
    // Make the link correct even without JS
    if (el.tagName === 'A') el.setAttribute('href', APP_URL);

    // Also handle button/div cases
    el.addEventListener('click', (e) => {
      // If it is already an <a> with the right href, let the browser handle it
      if (el.tagName === 'A' && el.getAttribute('href') === APP_URL) return;
      e.preventDefault();
      window.location.assign(APP_URL);
    });
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => wireOpenApp());
} else {
  wireOpenApp();
}

// Export for tests if needed
export { APP_URL, wireOpenApp };