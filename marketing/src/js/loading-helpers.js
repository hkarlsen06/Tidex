/**
 * Loading State Helper Functions
 * Provides consistent loading states across the application
 */

class LoadingManager {
    constructor() {
        this.activeLoaders = new Set();
    }

    /**
     * Show loading state on an element
     * @param {HTMLElement|string} element - Element or selector
     * @param {Object} options - Loading options
     */
    show(element, options = {}) {
        const el = typeof element === 'string' ? document.querySelector(element) : element;
        if (!el) return;

        const {
            type = 'spinner', // spinner, skeleton, overlay
            text = 'Laster...',
            preserveSize = true
        } = options;

        // Store original content
        const loaderId = `loader-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        this.activeLoaders.add({
            element: el,
            originalContent: el.innerHTML,
            originalClasses: el.className,
            loaderId
        });

        if (preserveSize) {
            el.style.minHeight = el.offsetHeight + 'px';
            el.style.minWidth = el.offsetWidth + 'px';
        }

        el.classList.add('loading');
        el.setAttribute('aria-busy', 'true');
        el.setAttribute('aria-label', text);

        switch (type) {
            case 'spinner':
                el.innerHTML = this.createSpinner(text);
                break;
            case 'skeleton':
                el.innerHTML = this.createSkeleton();
                break;
            case 'overlay':
                el.style.position = 'relative';
                el.appendChild(this.createOverlay(text));
                break;
        }

        return loaderId;
    }

    /**
     * Hide loading state
     * @param {HTMLElement|string} element - Element or selector
     */
    hide(element) {
        const el = typeof element === 'string' ? document.querySelector(element) : element;
        if (!el) return;

        // Find and restore original state
        const loaderData = Array.from(this.activeLoaders).find(loader => loader.element === el);
        if (loaderData) {
            el.innerHTML = loaderData.originalContent;
            el.className = loaderData.originalClasses;
            el.removeAttribute('aria-busy');
            el.removeAttribute('aria-label');
            el.style.minHeight = '';
            el.style.minWidth = '';
            
            // Remove overlay if it exists
            const overlay = el.querySelector('.loading-overlay');
            if (overlay) {
                overlay.remove();
            }

            this.activeLoaders.delete(loaderData);
        }
    }

    /**
     * Create spinner HTML
     */
    createSpinner(text) {
        return `
            <div class="loading-spinner" role="status" aria-label="${text}">
                <div class="spinner"></div>
                <span class="loading-text">${text}</span>
            </div>
        `;
    }

    /**
     * Create skeleton placeholder
     */
    createSkeleton() {
        return `
            <div class="skeleton-container">
                <div class="skeleton skeleton-line"></div>
                <div class="skeleton skeleton-line" style="width: 80%;"></div>
                <div class="skeleton skeleton-line" style="width: 60%;"></div>
            </div>
        `;
    }

    /**
     * Create overlay loader
     */
    createOverlay(text) {
        const overlay = document.createElement('div');
        overlay.className = 'loading-overlay';
        overlay.innerHTML = `
            <div class="loading-spinner" role="status" aria-label="${text}">
                <div class="spinner"></div>
                <span class="loading-text">${text}</span>
            </div>
        `;
        return overlay;
    }

    /**
     * Show loading state for async operation
     * @param {Promise} promise - Promise to track
     * @param {HTMLElement|string} element - Element to show loading on
     * @param {Object} options - Loading options
     */
    async trackPromise(promise, element, options = {}) {
        const loaderId = this.show(element, options);
        try {
            const result = await promise;
            this.hide(element);
            return result;
        } catch (error) {
            this.hide(element);
            throw error;
        }
    }
}

// CSS for loading states (add to existing CSS)
const loadingCSS = `
.loading-spinner {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    padding: var(--space-4);
}

.spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--border-color);
    border-top: 3px solid var(--primary);
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

.loading-text {
    color: var(--text-secondary);
    font-size: var(--font-size-sm);
}

.loading-overlay {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(2px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 10;
    border-radius: inherit;
}

.skeleton-container {
    padding: var(--space-2);
}

.skeleton-line {
    height: 16px;
    margin-bottom: var(--space-1);
}

.skeleton-line:last-child {
    margin-bottom: 0;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

/* Reduce motion for accessibility */
@media (prefers-reduced-motion: reduce) {
    .spinner {
        animation: none;
        border-top: 3px solid var(--primary);
    }
}
`;

// Add CSS to document if not already added
if (!document.querySelector('#loading-styles')) {
    const style = document.createElement('style');
    style.id = 'loading-styles';
    style.textContent = loadingCSS;
    document.head.appendChild(style);
}

// Create global instance
const LoadingHelper = new LoadingManager();

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = LoadingHelper;
} else {
    window.LoadingHelper = LoadingHelper;
}

/**
 * Usage examples:
 * 
 * // Show spinner
 * LoadingHelper.show('#my-button', { text: 'Lagrer...' });
 * 
 * // Track async operation
 * LoadingHelper.trackPromise(
 *     fetch('/api/data'),
 *     '#data-container',
 *     { type: 'skeleton', text: 'Laster data...' }
 * );
 * 
 * // Manual hide
 * LoadingHelper.hide('#my-button');
 */