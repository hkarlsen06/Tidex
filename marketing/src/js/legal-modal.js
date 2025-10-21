/**
 * Legal Modal Component
 * Handles display of Privacy Policy and Terms & Conditions
 */

class LegalModal {
    constructor() {
        this.modal = null;
        this.isOpen = false;
        this.init();
    }

    init() {
        this.createModal();
        this.bindEvents();
        
        // Ensure modal is hidden by default - CSS classes will handle this
        if (this.modal) {
            this.modal.classList.remove('active');
        }
    }

    createModal() {
        // Create modal container
        this.modal = document.createElement('div');
        this.modal.className = 'legal-modal';
        this.modal.setAttribute('role', 'dialog');
        this.modal.setAttribute('aria-labelledby', 'legal-modal-title');
        this.modal.setAttribute('aria-modal', 'true');

        // Modal content
        this.modal.innerHTML = `
            <div class="legal-modal-overlay"></div>
            <div class="legal-modal-container">
                <div class="legal-modal-header">
                    <h2 id="legal-modal-title">Personvernpolicy & Vilkår</h2>
                    <button class="legal-modal-close" aria-label="Lukk modal">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>
                
                <div class="legal-modal-tabs">
                    <button class="legal-tab active" data-tab="privacy">Personvernpolicy</button>
                    <button class="legal-tab" data-tab="terms">Vilkår og betingelser</button>
                </div>
                
                <div class="legal-modal-content">
                    <div class="legal-tab-content active" id="privacy-content">
                        <div class="legal-content-scroll">
                            <h3>Personvernpolicy</h3>
                            <p><strong>Sist oppdatert:</strong> August 2025</p>
                            
                            <h4>1. Introduksjon</h4>
                            <p>Denne personvernpolicyen beskriver hvordan Lønnskalkulator-applikasjonen ("vi", "vår" eller "oss") samler inn, bruker og beskytter din personlige informasjon når du bruker vår tjeneste.</p>
                            
                            <h4>2. Informasjon vi samler inn</h4>
                            <h5>2.1 Personlig informasjon</h5>
                            <ul>
                                <li><strong>Kontoinformasjon:</strong> E-postadresse, passord og fornavn når du oppretter en konto</li>
                                <li><strong>Profilinformasjon:</strong> Profilbilde (valgfritt), timelønnsønsker og brukerinnstillinger</li>
                                <li><strong>Ansattdata:</strong> Navn, e-postadresser, fødselsdatoer, timelønn og tariffnivåer for ansatte du administrerer</li>
                                <li><strong>Vaktdata:</strong> Arbeidsplaner, start-/sluttider, pauser og lønnsberegninger</li>
                            </ul>
                            
                            <h5>2.2 Teknisk informasjon</h5>
                            <ul>
                                <li><strong>Bruksdata:</strong> Hvordan du samhandler med applikasjonen, funksjoner som brukes og ytelsesmetrikker</li>
                                <li><strong>Enhetsinformasjon:</strong> Nettlesertype, operativsystem og enhetsidentifikatorer</li>
                                <li><strong>Loggdata:</strong> Serverlogger, feilrapporter og revisjonsspor</li>
                            </ul>
                            
                            <h4>3. Hvordan vi bruker din informasjon</h4>
                            <h5>3.1 Hovedformål</h5>
                            <ul>
                                <li><strong>Tjenesteytelse:</strong> For å levere lønnsberegningstjenester og administrere din konto</li>
                                <li><strong>Databehandling:</strong> For å beregne lønn, overtidsbetaling og kompensasjon basert på din input</li>
                                <li><strong>Brukeropplevelse:</strong> For å tilpasse din opplevelse og forbedre våre tjenester</li>
                            </ul>
                            
                            <h4>4. Datalagring og sikkerhet</h4>
                            <ul>
                                <li>Alle data lagres sikkert i Supabase skyinfrastruktur</li>
                                <li>Data behandles i samsvar med EUs databeskyttelsesforskrifter</li>
                                <li>Vi implementerer bransjestandard sikkerhetstiltak for å beskytte din informasjon</li>
                            </ul>
                            
                            <h4>5. Dine rettigheter</h4>
                            <ul>
                                <li>Få tilgang til, oppdater og slett din personlige informasjon</li>
                                <li>Eksporter dine data i standardformater</li>
                                <li>Be om fullstendig sletting av din konto og tilknyttet data</li>
                            </ul>
                            
                            <h4>6. Kontaktinformasjon</h4>
                            <p>For spørsmål om denne personvernpolicyen, kontakt oss på: <strong>kkarlsen06@kkarlsen.art</strong></p>
                        </div>
                    </div>
                    
                    <div class="legal-tab-content" id="terms-content">
                        <div class="legal-content-scroll">
                            <h3>Vilkår og betingelser</h3>
                            <p><strong>Sist oppdatert:</strong> August 2025</p>
                            
                            <h4>1. Godkjenning av vilkår</h4>
                            <p>Ved å få tilgang til og bruke Lønnskalkulator-applikasjonen ("Tjeneste") godtar og samtykker du til å være bundet av vilkårene og bestemmelsene i denne avtalen.</p>
                            
                            <h4>2. Beskrivelse av tjeneste</h4>
                            <p>Lønnskalkulatoren er en webbasert applikasjon som leverer:</p>
                            <ul>
                                <li>Lønnsberegningstjenester basert på arbeidsplaner og tariffavtaler</li>
                                <li>Ansattadministrasjon og vaktsporing</li>
                                <li>Lønnskalkulasjon og rapporteringsfunksjoner</li>
                                <li>Brukerkontoadministrasjon og datalagring</li>
                            </ul>
                            
                            <h4>3. Brukerkontoer og registrering</h4>
                            <ul>
                                <li>Du må oppgi nøyaktig, oppdatert og fullstendig informasjon under registrering</li>
                                <li>Du er ansvarlig for å opprettholde konfidensialiteten til dine kontotilganger</li>
                                <li>Du må være minst 13 år gammel for å opprette en konto</li>
                            </ul>
                            
                            <h4>4. Akseptabel bruk</h4>
                            <h5>4.1 Tillatte bruksområder</h5>
                            <ul>
                                <li>Personlige lønnsberegninger og ansattadministrasjon</li>
                                <li>Forretningsbruk for administrasjon av ansattlønn</li>
                                <li>Utdannings- og forskningsformål</li>
                            </ul>
                            
                            <h5>4.2 Forbudte bruksområder</h5>
                            <ul>
                                <li>Forsøk på å få uautorisert tilgang til systemet</li>
                                <li>Bruk av tjenesten til ulovlige eller svindelaktige aktiviteter</li>
                                <li>Forstyrrelse av tjenestens drift eller andre brukeres tilgang</li>
                            </ul>
                            
                            <h4>5. Tjenestebegrensninger</h4>
                            <ul>
                                <li>Tjenesten leveres "som den er" uten garantier av noe slag</li>
                                <li>Vi garanterer ikke nøyaktigheten av beregninger eller resultater</li>
                                <li>Vi er ikke ansvarlige for eventuelle tap relatert til lønnsberegninger eller forretningsbeslutninger</li>
                            </ul>
                            
                            <h4>6. Kontaktinformasjon</h4>
                            <p>For spørsmål om disse vilkårene, kontakt oss på: <strong>kkarlsen06@kkarlsen.art</strong></p>
                        </div>
                    </div>
                </div>
                
                <div class="legal-modal-footer">
                    <button class="btn btn-primary legal-modal-accept" id="legal-accept-btn">Jeg godtar</button>
                    <button class="btn btn-secondary legal-modal-decline" id="legal-decline-btn">Avslå</button>
                </div>
            </div>
        `;

        // Add to document
        document.body.appendChild(this.modal);
    }

    bindEvents() {
        // Close button
        const closeBtn = this.modal.querySelector('.legal-modal-close');
        closeBtn.addEventListener('click', () => this.close());

        // Overlay click
        const overlay = this.modal.querySelector('.legal-modal-overlay');
        overlay.addEventListener('click', () => this.close());

        // Tab switching
        const tabs = this.modal.querySelectorAll('.legal-tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', (e) => this.switchTab(e.target.dataset.tab));
        });

        // Accept/Decline buttons
        const acceptBtn = this.modal.querySelector('#legal-accept-btn');
        const declineBtn = this.modal.querySelector('#legal-decline-btn');
        
        if (acceptBtn) {
            acceptBtn.addEventListener('click', () => this.accept());
        }
        if (declineBtn) {
            declineBtn.addEventListener('click', () => this.decline());
        }

        // Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.isOpen) {
                this.close();
            }
        });
    }

    switchTab(tabName) {
        // Update active tab
        const tabs = this.modal.querySelectorAll('.legal-tab');
        const contents = this.modal.querySelectorAll('.legal-tab-content');
        
        tabs.forEach(tab => tab.classList.remove('active'));
        contents.forEach(content => content.classList.remove('active'));
        
        const targetTab = this.modal.querySelector(`[data-tab="${tabName}"]`);
        const targetContent = this.modal.querySelector(`#${tabName}-content`);
        
        if (targetTab) {
            targetTab.classList.add('active');
        }
        if (targetContent) {
            targetContent.classList.add('active');
        }
    }

    open() {
        
        // For login page, don't scroll to top
        const isLoginPage = window.location.pathname === '/login';
        
        if (!isLoginPage) {
            // Scroll to top before opening modal (only for landing page)
            window.scrollTo({
                top: 0,
                behavior: 'smooth'
            });
        }
        
        // Wait for scroll to complete before showing modal (or show immediately on login page)
        const delay = isLoginPage ? 0 : 300;
        setTimeout(() => {
            this.modal.classList.add('active');
            this.isOpen = true;
            document.body.style.overflow = 'hidden';
            
            // Focus management
            setTimeout(() => {
                this.modal.querySelector('.legal-modal-close').focus();
            }, 100);
        }, delay);
    }

    close() {
        this.modal.classList.remove('active');
        this.isOpen = false;
        document.body.style.overflow = '';
        
        // Remove landing page class when closing
        this.modal.classList.remove('landing-page');
    }

    accept() {
        // Trigger custom event for acceptance
        const event = new CustomEvent('legalAccepted', {
            detail: { accepted: true }
        });
        document.dispatchEvent(event);
        this.close();
    }

    decline() {
        // Trigger custom event for decline
        const event = new CustomEvent('legalDeclined', {
            detail: { accepted: false }
        });
        document.dispatchEvent(event);
        this.close();
    }

    // Method to show without accept/decline buttons (for info display)
    showInfo() {
        const footer = this.modal.querySelector('.legal-modal-footer');
        if (footer) {
            footer.style.display = 'none';
        }
        this.open();
    }

    // Method to show with accept/decline buttons (for consent)
    showConsent() {
        const footer = this.modal.querySelector('.legal-modal-footer');
        if (footer) {
            footer.style.display = 'flex';
        }
        this.open();
    }

    // Method specifically for landing page display with enhanced scroll behavior
    showFromLandingPage() {
        
        // Hide the footer with accept/decline buttons for landing page
        const footer = this.modal.querySelector('.legal-modal-footer');
        if (footer) {
            footer.style.display = 'none';
        }
        
        // Add landing page class for enhanced animation
        this.modal.classList.add('landing-page');
        
        // Check current scroll position and scroll smoothly to top
        const currentScroll = window.pageYOffset || document.documentElement.scrollTop;
        
        if (currentScroll > 100) {
            // Enhanced scroll to top for landing page with smooth behavior
            window.scrollTo({
                top: 0,
                behavior: 'smooth'
            });
            
            // Wait for scroll to complete before showing modal
            setTimeout(() => {
                this.showModalAfterScroll();
            }, 400);
        } else {
            // Already near top, show modal immediately
            this.showModalAfterScroll();
        }
    }
    
    // Helper method to show modal after scroll completion
    showModalAfterScroll() {
        this.modal.classList.add('active');
        this.isOpen = true;
        document.body.style.overflow = 'hidden';
        
        // Focus management with slight delay for better UX
        setTimeout(() => {
            this.modal.querySelector('.legal-modal-close').focus();
        }, 150);
    }

    destroy() {
        if (this.modal && this.modal.parentNode) {
            this.modal.parentNode.removeChild(this.modal);
        }
    }
}

// Export for use in other modules
export default LegalModal;
