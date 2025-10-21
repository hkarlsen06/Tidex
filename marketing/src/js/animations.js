// ═══════════════════════════════════════════════════════════════════════════
// PORTFOLIO ANIMATIONS
// ═══════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────
// PERFORMANCE UTILITIES
// ───────────────────────────────────────────────────────────────────────────

// Throttle function for performance-critical animations
function throttle(func, limit) {
    let inThrottle;
    return function() {
        const args = arguments;
        const context = this;
        if (!inThrottle) {
            func.apply(context, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    }
}

// Debounce function for resize events
// Duplicate debounce removed; using the earlier definition in this file

// ───────────────────────────────────────────────────────────────────────────
// INITIALIZATION
// ───────────────────────────────────────────────────────────────────────────

// Immediate scroll prevention - run first
(function() {
    // Prevent browser scroll restoration
    if ('scrollRestoration' in history) {
        history.scrollRestoration = 'manual';
    }
    
    // Single scroll to top function
    const scrollToTop = () => {
        window.scrollTo(0, 0);
        document.documentElement.scrollTop = 0;
        document.body.scrollTop = 0;
    };
    
    // Clear any hash from URL that might cause scrolling
    if (window.location.hash && window.location.hash !== '#') {
        history.replaceState(null, null, window.location.pathname + window.location.search);
    }
    
    // Force scroll to top immediately
    scrollToTop();
    
    // Single delayed scroll to top to handle any deferred scrolling
    setTimeout(scrollToTop, 50);
})();

// Ensure page starts at top on beforeunload
window.addEventListener('beforeunload', () => {
    window.scrollTo(0, 0);
});

// Prevent intersection observer from triggering scroll
let preventScrolling = true;
setTimeout(() => {
    preventScrolling = false;
}, 500);

document.addEventListener('DOMContentLoaded', () => {
    // Single scroll to top on DOM ready
    window.scrollTo(0, 0);

    // Initialize animations with proper sequencing to prevent stuttering
    initAnimationsSequentially();
});

// Initialize animations with staggered timing to prevent performance issues
async function initAnimationsSequentially() {
    // Start with essential functionality first
    initNavbar();

    // Small delay before starting visual animations
    await new Promise(resolve => setTimeout(resolve, 100));

    // Initialize scroll animations (most important for UX)
    initScrollAnimations();

    // Stagger the remaining animations to prevent simultaneous execution
    await new Promise(resolve => setTimeout(resolve, 150));
    initParallax();

    await new Promise(resolve => setTimeout(resolve, 100));
    initTypingEffect();

    await new Promise(resolve => setTimeout(resolve, 100));
    initHoverEffects();

    await new Promise(resolve => setTimeout(resolve, 50));
    initMobileMenu();

    await new Promise(resolve => setTimeout(resolve, 50));
    initMobileStats();
}

// ───────────────────────────────────────────────────────────────────────────
// NAVBAR FUNCTIONALITY
// ───────────────────────────────────────────────────────────────────────────
function initNavbar() {
    const navbar = document.querySelector('.navbar');
    if (!navbar) return;
    
    let lastScroll = 0;
    let ticking = false;
    
    const updateNavbar = () => {
        const currentScroll = window.pageYOffset;
        
        // Add background on scroll
        if (currentScroll > 50) {
            navbar.style.background = 'rgba(10, 10, 11, 0.95)';
            navbar.style.backdropFilter = 'blur(30px)';
        } else {
            navbar.style.background = 'rgba(10, 10, 11, 0.8)';
            navbar.style.backdropFilter = 'blur(20px)';
        }
        
        // Hide/show on scroll
        if (currentScroll > lastScroll && currentScroll > 200) {
            navbar.style.transform = 'translateY(-100%)';
        } else {
            navbar.style.transform = 'translateY(0)';
        }
        
        lastScroll = currentScroll;
        ticking = false;
    };
    
    window.addEventListener('scroll', () => {
        if (!ticking) {
            requestAnimationFrame(updateNavbar);
            ticking = true;
        }
    });
    
    // Smooth scroll for nav links
    document.querySelectorAll('.nav-link').forEach(link => {
        link.addEventListener('click', (e) => {
            const href = link.getAttribute('href');
            if (href.startsWith('#')) {
                e.preventDefault();
                const target = document.querySelector(href);
                if (target) {
                    target.scrollIntoView({ behavior: 'smooth' });
                }
            }
        });
    });
}

// ───────────────────────────────────────────────────────────────────────────
// SCROLL ANIMATIONS
// ───────────────────────────────────────────────────────────────────────────
function initScrollAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -100px 0px'
    };
    
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                // Use requestAnimationFrame for smoother animations
                requestAnimationFrame(() => {
                    entry.target.classList.add('animate-in');

                    // Stagger animations for child elements with reduced timing
                    const children = entry.target.querySelectorAll('.animate-child');
                    children.forEach((child, i) => {
                        // Reduced stagger time from 100ms to 60ms for smoother flow
                        setTimeout(() => {
                            requestAnimationFrame(() => {
                                child.classList.add('animate-in');
                            });
                        }, i * 60);
                    });
                });
            }
        });
    }, observerOptions);
    
    // Observe sections
    document.querySelectorAll('.section-header, .tech-card, .feature-item').forEach(el => {
        el.classList.add('animate-element');
        observer.observe(el);
    });
}

// ───────────────────────────────────────────────────────────────────────────
// PARALLAX EFFECTS
// ───────────────────────────────────────────────────────────────────────────
function initParallax() {
    const orbs = document.querySelectorAll('.gradient-orb');
    if (!orbs.length) return;
    
    let ticking = false;
    
    const updateParallax = (e) => {
        const x = e.clientX / window.innerWidth;
        const y = e.clientY / window.innerHeight;
        
        orbs.forEach((orb, i) => {
            const speed = (i + 1) * 0.2;
            const xPos = (x - 0.5) * speed * 30;
            const yPos = (y - 0.5) * speed * 30;
            
            orb.style.setProperty('--mouse-x', `${xPos}px`);
            orb.style.setProperty('--mouse-y', `${yPos}px`);
        });
        
        ticking = false;
    };
    
    window.addEventListener('mousemove', (e) => {
        if (!ticking) {
            requestAnimationFrame(() => updateParallax(e));
            ticking = true;
        }
    });
    
    // Subtle parallax on scroll
    let scrollTicking = false;
    
    const updateScrollParallax = () => {
        const scrolled = window.pageYOffset;
        
        orbs.forEach((orb, i) => {
            const speed = (i + 1) * 0.1;
            orb.style.setProperty('--scroll-y', `${scrolled * speed}px`);
        });
        
        scrollTicking = false;
    };
    
    window.addEventListener('scroll', () => {
        if (!scrollTicking) {
            requestAnimationFrame(updateScrollParallax);
            scrollTicking = true;
        }
    });
}

// ───────────────────────────────────────────────────────────────────────────
// TYPING EFFECT
// ───────────────────────────────────────────────────────────────────────────
function initTypingEffect() {
    // Typing effect disabled - using static subtitle now
    return;
    
    const phrases = [
        'Utvikler med øye for detaljer',
        'Elsker å løse avanserte problemer',
        'Bygger intuitive brukergrensesnitt',
        'Brenner for god brukeropplevelse',
        'Skaper løsninger som fungerer, hver gang'
    ];
    
    let currentPhrase = 0;
    let currentChar = 0;
    let isDeleting = false;
    let typingSpeed = 80; // Reduced from 100ms to 80ms
    let initialTextDeleted = false;
    
    function startScrollAnimation(futureText) {
        const currentText = subtitleText.textContent;
        subtitleText.textContent = futureText;
        
        const textWidth = subtitleText.scrollWidth;
        const containerWidth = subtitle.clientWidth;
        
        subtitleText.textContent = currentText;
        
        if (textWidth > containerWidth) {
            subtitle.classList.add('overflow-scroll');
            const overflowAmount = textWidth - containerWidth;
            const scrollDistance = -overflowAmount;
            subtitleText.style.transform = `translateX(${scrollDistance}px)`;
        } else {
            subtitle.classList.remove('overflow-scroll');
            subtitleText.style.transform = 'translateX(0)';
        }
    }
    
    function updateText(text) {
        startScrollAnimation(text);
        subtitleText.textContent = text;
    }
    
    function type() {
        if (!initialTextDeleted) {
            const currentText = subtitleText.textContent;
            if (currentText.length > 0) {
                updateText(currentText.substring(0, currentText.length - 1));
                setTimeout(type, 80);
                return;
            } else {
                initialTextDeleted = true;
                currentChar = 0;
                typingSpeed = 500;
            }
        }
        
        const phrase = phrases[currentPhrase];
        
        if (isDeleting) {
            updateText(phrase.substring(0, currentChar - 1));
            currentChar--;
            typingSpeed = 50;
        } else {
            updateText(phrase.substring(0, currentChar + 1));
            currentChar++;
            typingSpeed = 80; // Reduced from 100ms to 80ms
        }
        
        if (!isDeleting && currentChar === phrase.length) {
            typingSpeed = 2000;
            isDeleting = true;
        } else if (isDeleting && currentChar === 0) {
            isDeleting = false;
            currentPhrase = (currentPhrase + 1) % phrases.length;
            typingSpeed = 500;
            updateText('\u00A0');
        }
        
        setTimeout(type, typingSpeed);
    }
    
    // Listen for window resize to restart scroll animation
    window.addEventListener('resize', debounce(() => {
        startScrollAnimation(subtitleText.textContent);
    }, 100));
    
    // Start typing effect
    setTimeout(type, 2000); // Reduced from 4000ms to 2000ms
}

// ───────────────────────────────────────────────────────────────────────────
// HOVER EFFECTS
// ───────────────────────────────────────────────────────────────────────────
function initHoverEffects() {
    // Button ripple effect
    document.querySelectorAll('.btn').forEach(btn => {
        btn.addEventListener('click', function(e) {
            const ripple = document.createElement('span');
            const rect = this.getBoundingClientRect();
            const size = Math.max(rect.width, rect.height);
            const x = e.clientX - rect.left - size / 2;
            const y = e.clientY - rect.top - size / 2;
            
            ripple.style.width = ripple.style.height = size + 'px';
            ripple.style.left = x + 'px';
            ripple.style.top = y + 'px';
            ripple.classList.add('ripple');
            
            this.appendChild(ripple);
            
            setTimeout(() => ripple.remove(), 600);
        });
    });
    
    // Card tilt effect - disabled on mobile, optimized for performance
    if (window.innerWidth > 768) {
        document.querySelectorAll('.tech-card, .floating-card').forEach(card => {
            let isAnimating = false;

            card.addEventListener('mousemove', (e) => {
                if (isAnimating) return; // Throttle animation calls

                isAnimating = true;
                requestAnimationFrame(() => {
                    const rect = card.getBoundingClientRect();
                    const x = e.clientX - rect.left;
                    const y = e.clientY - rect.top;

                    const centerX = rect.width / 2;
                    const centerY = rect.height / 2;

                    const rotateX = (y - centerY) / 10;
                    const rotateY = (centerX - x) / 10;

                    card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
                    isAnimating = false;
                });
            });

            card.addEventListener('mouseleave', () => {
                requestAnimationFrame(() => {
                    card.style.transform = 'perspective(1000px) rotateX(0) rotateY(0)';
                });
            });
        });
    }
}

// ───────────────────────────────────────────────────────────────────────────
// MOBILE MENU
// ───────────────────────────────────────────────────────────────────────────
function initMobileMenu() {
    const toggle = document.querySelector('.nav-toggle');
    const menu = document.querySelector('.nav-menu');
    
    if (toggle && menu) {
        toggle.addEventListener('click', () => {
            menu.classList.toggle('active');
            toggle.classList.toggle('active');
        });
    }
}

// ───────────────────────────────────────────────────────────────────────────
// MOBILE STATS HANDLING
// ───────────────────────────────────────────────────────────────────────────
function initMobileStats() {
    const heroStats = document.querySelector('.hero-stats');
    if (!heroStats) return;
    
    let visualViewportResizeListener = null;
    let visualViewportScrollListener = null;
    let keyboardResizeListener = null;
    let isMobile = false;
    let initialHeight = 0;
    
    const ensureCorrectPositioning = () => {
        if (window.innerWidth <= 768) {
            heroStats.style.left = '50%';
            heroStats.style.transform = 'translateX(-50%)';
            heroStats.style.position = 'fixed';
            heroStats.style.opacity = '1';
            heroStats.style.display = 'flex';
        }
    };
    
    const updateStatsPosition = () => {
        if (window.visualViewport) {
            const offset = window.visualViewport.height < window.innerHeight ? 
                window.innerHeight - window.visualViewport.height : 0;
            
            heroStats.style.bottom = `calc(var(--space-md) + ${offset}px)`;
        }
        ensureCorrectPositioning();
    };
    
    const handleKeyboardToggle = debounce(() => {
        if (!isMobile) return;
        
        const currentHeight = window.innerHeight;
        const heightDiff = initialHeight - currentHeight;
        
        if (heightDiff > 150) {
            heroStats.style.display = 'none';
        } else {
            heroStats.style.display = 'flex';
        }
    }, 100);
    
    const removeExistingListeners = () => {
        if (visualViewportResizeListener && window.visualViewport) {
            window.visualViewport.removeEventListener('resize', visualViewportResizeListener);
            visualViewportResizeListener = null;
        }
        
        if (visualViewportScrollListener && window.visualViewport) {
            window.visualViewport.removeEventListener('scroll', visualViewportScrollListener);
            visualViewportScrollListener = null;
        }
        
        if (keyboardResizeListener) {
            window.removeEventListener('resize', keyboardResizeListener);
            keyboardResizeListener = null;
        }
    };
    
    const addMobileListeners = () => {
        if (window.visualViewport) {
            visualViewportResizeListener = updateStatsPosition;
            visualViewportScrollListener = updateStatsPosition;
            
            window.visualViewport.addEventListener('resize', visualViewportResizeListener);
            window.visualViewport.addEventListener('scroll', visualViewportScrollListener);
            updateStatsPosition();
        }
        
        keyboardResizeListener = handleKeyboardToggle;
        window.addEventListener('resize', keyboardResizeListener);
    };
    
    const handleViewportChange = () => {
        const shouldBeMobile = window.innerWidth <= 768;
        
        if (shouldBeMobile !== isMobile) {
            removeExistingListeners();
            
            isMobile = shouldBeMobile;
            
            if (isMobile) {
                initialHeight = window.innerHeight;
                ensureCorrectPositioning();
                addMobileListeners();
            } else {
                heroStats.style.bottom = '';
                heroStats.style.display = '';
                heroStats.style.left = '';
                heroStats.style.transform = '';
                heroStats.style.position = '';
                heroStats.style.opacity = '';
            }
        }
    };
    
    handleViewportChange();
    
    if (isMobile) {
        initialHeight = window.innerHeight;
    }
    
    ensureCorrectPositioning();
    window.addEventListener('resize', debounce(handleViewportChange, 100));
}

// ───────────────────────────────────────────────────────────────────────────
// UTILITY FUNCTIONS
// ───────────────────────────────────────────────────────────────────────────
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// ───────────────────────────────────────────────────────────────────────────
// ANIMATION CSS INJECTION
// ───────────────────────────────────────────────────────────────────────────
const animationStyles = `
    .animate-element {
        opacity: 0;
        transform: translateY(30px);
        transition: all 0.4s ease-out; /* Reduced from 0.8s */
    }

    .animate-element.animate-in {
        opacity: 1;
        transform: translateY(0);
    }

    .animate-child {
        opacity: 0;
        transform: translateX(-20px);
        transition: all 0.3s ease-out; /* Reduced from 0.6s */
    }

    .animate-child.animate-in {
        opacity: 1;
        transform: translateX(0);
    }
    
    .ripple {
        position: absolute;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.5);
        transform: scale(0);
        animation: ripple-animation 0.6s ease-out;
        pointer-events: none;
    }
    
    @keyframes ripple-animation {
        to {
            transform: scale(4);
            opacity: 0;
        }
    }
    
    .nav-menu.active {
        display: flex !important;
        position: fixed;
        top: 60px;
        right: 20px;
        flex-direction: column;
        background: var(--bg-card);
        padding: var(--space-lg);
        border-radius: 12px;
        box-shadow: var(--shadow-xl);
        border: 1px solid var(--border-color);
    }
    
    .nav-toggle.active span:nth-child(1) {
        transform: rotate(45deg) translate(5px, 5px);
    }
    
    .nav-toggle.active span:nth-child(2) {
        opacity: 0;
    }
    
    .nav-toggle.active span:nth-child(3) {
        transform: rotate(-45deg) translate(7px, -6px);
    }
`;

// Inject animation styles
const styleSheet = document.createElement('style');
styleSheet.textContent = animationStyles;
document.head.appendChild(styleSheet);

// ───────────────────────────────────────────────────────────────────────────
// PERFORMANCE MONITORING
// ───────────────────────────────────────────────────────────────────────────
if ('performance' in window) {
    window.addEventListener('load', () => {
        const perfData = window.performance.timing;
        const pageLoadTime = perfData.loadEventEnd - perfData.navigationStart;
    });
}

