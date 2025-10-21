import './css/style.css';
import './css/legal-modal.css';
import './js/apiBase.js';
import './js/loading-helpers.js';
import './js/error-handling.js';
import './js/redirect.js';
import './js/animations.js';

// Legal modal functionality
import LegalModal from './js/legal-modal.js';

// Initialize legal modal
document.addEventListener('DOMContentLoaded', () => {
    // Show checkout/portal status toast if present
    try {
        const params = new URLSearchParams(window.location.search);
        const status = params.get('checkout');
        if (status && window.ErrorHelper) {
            if (status === 'success') {
                window.ErrorHelper.showSuccess('Betaling fullført!');
            } else if (status === 'cancel' || status === 'error' || status === 'failed') {
                window.ErrorHelper.showError('Betaling ble avbrutt eller feilet.');
            }
            params.delete('checkout');
        }
        const portal = params.get('portal');
        if (portal && window.ErrorHelper) {
            if (portal === 'done') {
                window.ErrorHelper.showSuccess('Abonnement oppdatert!');
            }
            params.delete('portal');
        }
        if (status || portal) {
            const base = window.location.origin + window.location.pathname + (params.toString() ? `?${params}` : '');
            window.history.replaceState({}, document.title, base);
        }
    } catch (_) {}

    const legalModal = new LegalModal();
    // Auto-open legal modal when visiting /privacy or /terms directly
    try {
        const normalizedPath = window.location.pathname.replace(/\/+$/, ''); // strip trailing slash(es)
        if (normalizedPath === '/privacy') {
            legalModal.showFromLandingPage();
            legalModal.switchTab('privacy');
        } else if (normalizedPath === '/terms') {
            legalModal.showFromLandingPage();
            legalModal.switchTab('terms');
        }
    } catch (_) {}


    // Add Personvernerklæring button to footer
    const footer = document.querySelector('.footer');
    if (footer) {
        const footerLinks = footer.querySelector('.footer-links');
        if (footerLinks) {
            const privacyBtn = document.createElement('button');
            privacyBtn.type = 'button';
            privacyBtn.className = 'btn btn-secondary';
            privacyBtn.setAttribute('aria-label', 'Åpne personvernerklæringen');
            privacyBtn.textContent = 'Personvernerklæring';
            privacyBtn.addEventListener('click', (e) => {
                e.preventDefault();
                legalModal.showFromLandingPage();
                legalModal.switchTab('privacy');
            });

            footerLinks.appendChild(privacyBtn);
        }
    }

    // Hook up inline legal links on landing (if present)
    const legalLinks = document.querySelectorAll('[data-legal]');
    if (legalLinks.length) {
        legalLinks.forEach((el) => {
            el.addEventListener('click', (e) => {
                e.preventDefault();
                const tab = el.getAttribute('data-legal') === 'terms' ? 'terms' : 'privacy';
                // Show modal tailored for landing, then switch tab
                legalModal.showFromLandingPage();
                legalModal.switchTab(tab);
            });
        });
    }

    // Match CTA width to tagline width on mobile for visual harmony
    const adjustCtaWidth = () => {
        const tagline = document.querySelector('.tagline');
        const ctaBtn = document.querySelector('.open-app-btn');
        if (!tagline || !ctaBtn) return;

        const isMobile = window.innerWidth <= 600;
        if (isMobile) {
            // Defer to ensure fonts/layout have settled
            requestAnimationFrame(() => {
                const rect = tagline.getBoundingClientRect();
                const target = Math.ceil(rect.width * (2 / 3));

                // Measure natural (intrinsic) button width to avoid wrapping smaller than content
                const prevWidth = ctaBtn.style.width;
                ctaBtn.style.width = 'auto';
                const natural = Math.ceil(ctaBtn.getBoundingClientRect().width);
                // Restore will be overridden just below
                ctaBtn.style.width = prevWidth;

                const finalWidth = Math.max(target, natural);
                ctaBtn.style.width = finalWidth > 0 ? `${finalWidth}px` : '';
                ctaBtn.style.maxWidth = '100%';
            });
        } else {
            ctaBtn.style.width = '';
            ctaBtn.style.maxWidth = '';
        }
    };

    // Simple debounce to avoid thrashing on resize
    let resizeT;
    window.addEventListener('resize', () => {
        clearTimeout(resizeT);
        resizeT = setTimeout(adjustCtaWidth, 100);
    });
    window.addEventListener('orientationchange', () => setTimeout(adjustCtaWidth, 150));
    // Initial run
    adjustCtaWidth();
});
