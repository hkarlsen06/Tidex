/**
 * Error Handling and User Feedback System
 * Provides consistent error messaging and recovery guidance
 */

class ErrorHandler {
    constructor() {
        this.messageContainer = null;
        this.init();
    }

    /**
     * Initialize error handler
     */
    init() {
        // Wait for DOM to be ready before creating container
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.initContainer());
        } else {
            this.initContainer();
        }
    }
    
    /**
     * Initialize the message container
     */
    initContainer() {
        // Create message container if it doesn't exist
        if (!document.querySelector('#error-messages')) {
            this.createMessageContainer();
        }
        this.messageContainer = document.querySelector('#error-messages');
    }

    /**
     * Create global message container
     */
    createMessageContainer() {
        const container = document.createElement('div');
        container.id = 'error-messages';
        container.className = 'message-container';
        container.setAttribute('aria-live', 'polite');
        container.setAttribute('aria-atomic', 'true');
        document.body.appendChild(container);
    }

    /**
     * Norwegian-friendly error messages
     */
    getErrorMessages() {
        return {
            // Form validation
            'required': 'Dette feltet er påkrevd',
            'email': 'Vennligst skriv inn en gyldig e-postadresse',
            'minLength': 'Passordet må være minst 8 tegn langt',
            'passwordMismatch': 'Passordene stemmer ikke overens',
            'invalidTime': 'Vennligst skriv inn en gyldig tid (HH:MM)',
            'invalidDate': 'Vennligst velg en gyldig dato',
            'startAfterEnd': 'Starttid må være før sluttid',
            
            // Network and API
            'network': 'Kunne ikke koble til serveren. Sjekk internettforbindelsen din og prøv igjen.',
            'timeout': 'Forespørselen tok for lang tid. Prøv igjen senere.',
            'serverError': 'Noe gikk galt på serveren. Prøv igjen om litt.',
            'notFound': 'Kunne ikke finne den forespurte ressursen.',
            'unauthorized': 'Du har ikke tilgang til denne ressursen. Logg inn på nytt.',
            'forbidden': 'Du har ikke tillatelse til å utføre denne handlingen.',
            
            // Application specific
            'saveError': 'Kunne ikke lagre endringene. Prøv igjen.',
            'loadError': 'Kunne ikke laste data. Oppdater siden og prøv igjen.',
            'deleteError': 'Kunne ikke slette elementet. Prøv igjen.',
            'exportError': 'Kunne ikke eksportere data. Prøv igjen.',
            'importError': 'Kunne ikke importere data. Sjekk at filen er gyldig.',
            
            // Generic
            'unknown': 'En uventet feil oppstod. Prøv igjen eller kontakt support.',
            'retry': 'Prøv igjen',
            'contact': 'Kontakt support hvis problemet vedvarer'
        };
    }

    /**
     * Show error message
     * @param {string|Error} error - Error message or Error object
     * @param {Object} options - Display options
     */
    showError(error, options = {}) {
        const {
            type = 'error',
            duration = 5000,
            actionText = null,
            actionCallback = null,
            persistent = false
        } = options;

        const message = this.formatError(error);
        const messageElement = this.createMessage(message, type, {
            actionText,
            actionCallback,
            persistent
        });

        this.messageContainer.appendChild(messageElement);

        // Auto-remove non-persistent messages
        if (!persistent && duration > 0) {
            setTimeout(() => {
                this.removeMessage(messageElement);
            }, duration);
        }

        return messageElement;
    }

    /**
     * Show success message
     * @param {string} message - Success message
     * @param {Object} options - Display options
     */
    showSuccess(message, options = {}) {
        return this.showError(message, { ...options, type: 'success' });
    }

    /**
     * Show warning message
     * @param {string} message - Warning message
     * @param {Object} options - Display options
     */
    showWarning(message, options = {}) {
        return this.showError(message, { ...options, type: 'warning' });
    }

    /**
     * Show info message
     * @param {string} message - Info message
     * @param {Object} options - Display options
     */
    showInfo(message, options = {}) {
        return this.showError(message, { ...options, type: 'info' });
    }

    /**
     * Format error for display
     * @param {string|Error} error - Error to format
     */
    formatError(error) {
        const messages = this.getErrorMessages();
        
        if (typeof error === 'string') {
            return messages[error] || error;
        }
        
        if (error instanceof Error) {
            // Check for specific error types
            if (error.message.includes('NetworkError') || error.message.includes('fetch')) {
                return messages.network;
            }
            if (error.message.includes('timeout')) {
                return messages.timeout;
            }
            if (error.status === 401 || error.message.includes('Unauthorized')) {
                return messages.unauthorized;
            }
            if (error.status === 403 || error.message.includes('Forbidden')) {
                return messages.forbidden;
            }
            if (error.status === 404 || error.message.includes('Not Found')) {
                return messages.notFound;
            }
            if (error.status >= 500) {
                return messages.serverError;
            }
            
            return error.message || messages.unknown;
        }
        
        return messages.unknown;
    }

    /**
     * Create message element
     * @param {string} message - Message text
     * @param {string} type - Message type (error, success, warning, info)
     * @param {Object} options - Additional options
     */
    createMessage(message, type, options = {}) {
        const { actionText, actionCallback, persistent } = options;

        const messageEl = document.createElement('div');
        messageEl.className = `message message-${type}`;
        messageEl.setAttribute('role', type === 'error' ? 'alert' : 'status');

        const contentEl = document.createElement('div');
        contentEl.className = 'message-content';

        const iconEl = document.createElement('div');
        iconEl.className = 'message-icon';
        iconEl.textContent = this.getIcon(type);

        const textEl = document.createElement('div');
        textEl.className = 'message-text';
        textEl.textContent = message;

        const actionsEl = document.createElement('div');
        actionsEl.className = 'message-actions';

        if (actionText) {
            const actionBtn = document.createElement('button');
            actionBtn.className = 'message-action';
            actionBtn.setAttribute('aria-label', actionText);
            actionBtn.textContent = actionText;
            actionsEl.appendChild(actionBtn);
        }

        if (!persistent) {
            const closeBtn = document.createElement('button');
            closeBtn.className = 'message-close';
            closeBtn.setAttribute('aria-label', 'Lukk melding');
            closeBtn.textContent = '×';
            actionsEl.appendChild(closeBtn);
        }

        contentEl.appendChild(iconEl);
        contentEl.appendChild(textEl);
        contentEl.appendChild(actionsEl);
        messageEl.appendChild(contentEl);

        // Add event listeners
        const closeBtn = messageEl.querySelector('.message-close');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.removeMessage(messageEl));
        }

        const actionBtn = messageEl.querySelector('.message-action');
        if (actionBtn && actionCallback) {
            actionBtn.addEventListener('click', actionCallback);
        }

        // Add entry animation
        requestAnimationFrame(() => {
            messageEl.classList.add('message-enter');
        });

        return messageEl;
    }

    /**
     * Get icon for message type
     * @param {string} type - Message type
     */
    getIcon(type) {
        const icons = {
            error: '⚠️',
            success: '✅',
            warning: '⚠️',
            info: 'ℹ️'
        };
        return icons[type] || icons.info;
    }

    /**
     * Remove message element
     * @param {HTMLElement} messageElement - Message to remove
     */
    removeMessage(messageElement) {
        if (!messageElement || !messageElement.parentNode) return;

        messageElement.classList.add('message-exit');
        
        // Use transitionend event instead of setTimeout for better timing
        const handleTransitionEnd = (event) => {
            if (event.target === messageElement) {
                messageElement.removeEventListener('transitionend', handleTransitionEnd);
                if (messageElement.parentNode) {
                    messageElement.parentNode.removeChild(messageElement);
                }
            }
        };
        
        messageElement.addEventListener('transitionend', handleTransitionEnd);
        
        // Fallback timeout in case transition doesn't fire
        setTimeout(() => {
            if (messageElement.parentNode) {
                messageElement.removeEventListener('transitionend', handleTransitionEnd);
                messageElement.parentNode.removeChild(messageElement);
            }
        }, 350);
    }

    /**
     * Clear all messages
     */
    clearAll() {
        const messages = this.messageContainer.querySelectorAll('.message');
        messages.forEach(message => this.removeMessage(message));
    }

    /**
     * Handle form validation errors
     * @param {HTMLFormElement} form - Form element
     * @param {Object} errors - Validation errors
     */
    showFormErrors(form, errors) {
        // Clear existing errors
        form.querySelectorAll('.form-error').forEach(error => error.remove());
        form.querySelectorAll('.error').forEach(field => field.classList.remove('error'));

        const messages = this.getErrorMessages();

        Object.entries(errors).forEach(([fieldName, errorType]) => {
            const field = form.querySelector(`[name="${fieldName}"], #${fieldName}`);
            if (field) {
                field.classList.add('error');
                
                const errorEl = document.createElement('span');
                errorEl.className = 'form-error';
                errorEl.textContent = messages[errorType] || errorType;
                errorEl.setAttribute('role', 'alert');
                
                field.parentNode.insertBefore(errorEl, field.nextSibling);
            }
        });
    }

    /**
     * Handle async operation with error handling
     * @param {Promise|Function} promiseOrFactory - Promise to handle or function that returns a promise
     * @param {Object} options - Error handling options
     */
    async handleAsync(promiseOrFactory, options = {}) {
        const {
            successMessage = null,
            errorMessage = null,
            showLoading = true,
            loadingElement = null
        } = options;

        // Support both direct promises and factory functions for proper retry functionality
        const getPromise = typeof promiseOrFactory === 'function' 
            ? promiseOrFactory 
            : () => promiseOrFactory;

        try {
            if (showLoading && loadingElement && window.LoadingHelper) {
                window.LoadingHelper.show(loadingElement);
            }

            const result = await getPromise();

            if (successMessage) {
                this.showSuccess(successMessage);
            }

            return result;
        } catch (error) {
            console.error('Async operation failed:', error);
            
            const message = errorMessage || this.formatError(error);
            this.showError(message, {
                actionText: 'Prøv igjen',
                actionCallback: () => this.handleAsync(getPromise, options)
            });
            
            throw error;
        } finally {
            if (showLoading && loadingElement && window.LoadingHelper) {
                window.LoadingHelper.hide(loadingElement);
            }
        }
    }
}

// CSS for error messages
const errorCSS = `
.message-container {
    position: fixed;
    top: 20px;
    right: 20px;
    z-index: 9999;
    max-width: 400px;
    pointer-events: none;
}

.message {
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    margin-bottom: var(--space-2);
    opacity: 0;
    transform: translateX(100%);
    transition: all 0.3s ease;
    pointer-events: auto;
    box-shadow: var(--shadow-lg);
}

.message-enter {
    opacity: 1;
    transform: translateX(0);
}

.message-exit {
    opacity: 0;
    transform: translateX(100%);
}

.message-error {
    border-left: 4px solid var(--error);
}

.message-success {
    border-left: 4px solid var(--success);
}

.message-warning {
    border-left: 4px solid var(--warning);
}

.message-info {
    border-left: 4px solid var(--info);
}

.message-content {
    display: flex;
    align-items: flex-start;
    padding: var(--space-3);
    gap: var(--space-2);
}

.message-icon {
    font-size: 18px;
    flex-shrink: 0;
}

.message-text {
    flex: 1;
    color: var(--text-primary);
    line-height: 1.4;
}

.message-actions {
    display: flex;
    gap: var(--space-1);
    flex-shrink: 0;
}

.message-action, .message-close {
    background: none;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    transition: all 150ms ease;
}

.message-action:hover, .message-close:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
}

.message-close {
    font-size: 16px;
    line-height: 1;
}

.form-error {
    color: var(--error);
    font-size: var(--font-size-sm);
    margin-top: var(--space-1);
    display: block;
}

@media (max-width: 768px) {
    .message-container {
        left: 10px;
        right: 10px;
        top: 10px;
        max-width: none;
    }
}
`;

// Add CSS to document if not already added
if (!document.querySelector('#error-styles')) {
    const style = document.createElement('style');
    style.id = 'error-styles';
    style.textContent = errorCSS;
    document.head.appendChild(style);
}

// Create global instance
const ErrorHelper = new ErrorHandler();

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = ErrorHelper;
} else {
    window.ErrorHelper = ErrorHelper;
}

/**
 * Usage examples:
 * 
 * // Show error
 * ErrorHelper.showError('network');
 * 
 * // Show success
 * ErrorHelper.showSuccess('Data lagret!');
 * 
 * // Handle async operation (with retry support)
 * ErrorHelper.handleAsync(
 *     () => fetch('/api/save'),  // Pass a function that returns a new promise
 *     { 
 *         successMessage: 'Lagret!',
 *         loadingElement: '#save-button'
 *     }
 * );
 * 
 * // For backward compatibility, direct promises still work (but without retry)
 * ErrorHelper.handleAsync(
 *     fetch('/api/data'),
 *     { successMessage: 'Data hentet!' }
 * );
 * 
 * // Form validation
 * ErrorHelper.showFormErrors(form, {
 *     email: 'email',
 *     password: 'minLength'
 * });
 */