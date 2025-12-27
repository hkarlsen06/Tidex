import { describe, it, expect } from 'vitest';
import {
  detectInputType,
  isValidNorwegianPhone,
  normalizePhoneToE164,
  formatPhoneForDisplay,
  stripCountryCode,
  isValidEmail,
} from '@/lib/validation/phone';

describe('validation/phone', () => {
  describe('detectInputType', () => {
    it('should detect email addresses', () => {
      expect(detectInputType('user@example.com')).toBe('email');
      expect(detectInputType('test.user@domain.no')).toBe('email');
      expect(detectInputType('name+tag@gmail.com')).toBe('email');
    });

    it('should detect 8-digit Norwegian phone numbers', () => {
      expect(detectInputType('12345678')).toBe('phone');
      expect(detectInputType('98765432')).toBe('phone');
      expect(detectInputType('40000000')).toBe('phone');
    });

    it('should detect phone with spaces as phone', () => {
      expect(detectInputType('12 345 678')).toBe('phone');
      expect(detectInputType('123 456 78')).toBe('phone');
      expect(detectInputType('  12345678  ')).toBe('phone');
    });

    it('should return unknown for invalid input', () => {
      expect(detectInputType('1234567')).toBe('unknown'); // 7 digits
      expect(detectInputType('123456789')).toBe('unknown'); // 9 digits
      expect(detectInputType('abcd1234')).toBe('unknown'); // Letters and numbers
      expect(detectInputType('')).toBe('unknown');
      expect(detectInputType('random text')).toBe('unknown');
    });

    it('should handle edge cases', () => {
      expect(detectInputType('   ')).toBe('unknown');
      expect(detectInputType('@')).toBe('email'); // Contains @
      expect(detectInputType('12345678@')).toBe('email'); // Phone with @ becomes email
    });
  });

  describe('isValidNorwegianPhone', () => {
    it('should validate 8-digit Norwegian phone numbers', () => {
      expect(isValidNorwegianPhone('12345678')).toBe(true);
      expect(isValidNorwegianPhone('98765432')).toBe(true);
      expect(isValidNorwegianPhone('40000000')).toBe(true);
      expect(isValidNorwegianPhone('99999999')).toBe(true);
    });

    it('should accept phone numbers with spaces', () => {
      expect(isValidNorwegianPhone('12 345 678')).toBe(true);
      expect(isValidNorwegianPhone('123 456 78')).toBe(true);
      expect(isValidNorwegianPhone('1 2 3 4 5 6 7 8')).toBe(true);
    });

    it('should trim whitespace', () => {
      expect(isValidNorwegianPhone('  12345678  ')).toBe(true);
      expect(isValidNorwegianPhone('\n12345678\t')).toBe(true);
    });

    it('should reject invalid phone numbers', () => {
      expect(isValidNorwegianPhone('1234567')).toBe(false); // Too short
      expect(isValidNorwegianPhone('123456789')).toBe(false); // Too long
      expect(isValidNorwegianPhone('abcd1234')).toBe(false); // Contains letters
      expect(isValidNorwegianPhone('1234-5678')).toBe(false); // Contains dash
      expect(isValidNorwegianPhone('+4712345678')).toBe(false); // With country code
      expect(isValidNorwegianPhone('')).toBe(false);
    });
  });

  describe('normalizePhoneToE164', () => {
    it('should convert 8-digit Norwegian phone to E.164 format', () => {
      expect(normalizePhoneToE164('12345678')).toBe('+4712345678');
      expect(normalizePhoneToE164('98765432')).toBe('+4798765432');
      expect(normalizePhoneToE164('40000000')).toBe('+4740000000');
    });

    it('should handle phone numbers with spaces', () => {
      expect(normalizePhoneToE164('12 345 678')).toBe('+4712345678');
      expect(normalizePhoneToE164('123 456 78')).toBe('+4712345678');
    });

    it('should trim whitespace', () => {
      expect(normalizePhoneToE164('  12345678  ')).toBe('+4712345678');
    });

    it('should throw error for invalid phone numbers', () => {
      expect(() => normalizePhoneToE164('1234567')).toThrow('Invalid Norwegian phone number');
      expect(() => normalizePhoneToE164('123456789')).toThrow('Invalid Norwegian phone number');
      expect(() => normalizePhoneToE164('abcd1234')).toThrow('Invalid Norwegian phone number');
      expect(() => normalizePhoneToE164('')).toThrow('Invalid Norwegian phone number');
    });
  });

  describe('formatPhoneForDisplay', () => {
    it('should format 8-digit phone as XXX XX XXX', () => {
      expect(formatPhoneForDisplay('12345678')).toBe('123 45 678');
      expect(formatPhoneForDisplay('98765432')).toBe('987 65 432');
      expect(formatPhoneForDisplay('40000000')).toBe('400 00 000');
    });

    it('should handle E.164 format and strip country code', () => {
      expect(formatPhoneForDisplay('+4712345678')).toBe('123 45 678');
      expect(formatPhoneForDisplay('+4798765432')).toBe('987 65 432');
    });

    it('should handle phone with 47 prefix (without +)', () => {
      expect(formatPhoneForDisplay('4712345678')).toBe('123 45 678');
      expect(formatPhoneForDisplay('4798765432')).toBe('987 65 432');
    });

    it('should handle phone with spaces (normalize first)', () => {
      expect(formatPhoneForDisplay('123 45 678')).toBe('123 45 678');
      expect(formatPhoneForDisplay('12 345 678')).toBe('123 45 678');
    });

    it('should trim whitespace', () => {
      expect(formatPhoneForDisplay('  12345678  ')).toBe('123 45 678');
      expect(formatPhoneForDisplay('  +4712345678  ')).toBe('123 45 678');
    });

    it('should return input as-is for invalid lengths', () => {
      expect(formatPhoneForDisplay('1234567')).toBe('1234567'); // Too short
      expect(formatPhoneForDisplay('123456789')).toBe('123456789'); // Too long
      expect(formatPhoneForDisplay('')).toBe('');
    });

    it('should handle already formatted input', () => {
      const formatted = formatPhoneForDisplay('12345678');
      expect(formatPhoneForDisplay(formatted)).toBe('123 45 678');
    });
  });

  describe('stripCountryCode', () => {
    it('should remove +47 prefix', () => {
      expect(stripCountryCode('+4712345678')).toBe('12345678');
      expect(stripCountryCode('+4798765432')).toBe('98765432');
    });

    it('should return input as-is if no +47 prefix', () => {
      expect(stripCountryCode('12345678')).toBe('12345678');
      expect(stripCountryCode('98765432')).toBe('98765432');
    });

    it('should trim whitespace', () => {
      expect(stripCountryCode('  +4712345678  ')).toBe('12345678');
      expect(stripCountryCode('  12345678  ')).toBe('12345678');
    });

    it('should handle edge cases', () => {
      expect(stripCountryCode('+47')).toBe('');
      expect(stripCountryCode('')).toBe('');
      expect(stripCountryCode('   ')).toBe('');
    });

    it('should not strip other country codes', () => {
      expect(stripCountryCode('+4612345678')).toBe('+4612345678'); // Sweden
      expect(stripCountryCode('+1234567890')).toBe('+1234567890'); // USA
    });
  });

  describe('isValidEmail', () => {
    it('should validate correct email addresses', () => {
      expect(isValidEmail('user@example.com')).toBe(true);
      expect(isValidEmail('test.user@domain.no')).toBe(true);
      expect(isValidEmail('name+tag@gmail.com')).toBe(true);
      expect(isValidEmail('user123@sub.domain.com')).toBe(true);
      expect(isValidEmail('a@b.c')).toBe(true);
    });

    it('should trim whitespace', () => {
      expect(isValidEmail('  user@example.com  ')).toBe(true);
      expect(isValidEmail('\nuser@example.com\t')).toBe(true);
    });

    it('should reject invalid email addresses', () => {
      expect(isValidEmail('notanemail')).toBe(false);
      expect(isValidEmail('missing@domain')).toBe(false);
      expect(isValidEmail('@example.com')).toBe(false);
      expect(isValidEmail('user@')).toBe(false);
      expect(isValidEmail('user @example.com')).toBe(false); // Space in local part
      expect(isValidEmail('user@example .com')).toBe(false); // Space in domain
      expect(isValidEmail('')).toBe(false);
      expect(isValidEmail('   ')).toBe(false);
    });

    it('should reject email without TLD', () => {
      expect(isValidEmail('user@example')).toBe(false);
    });

    it('should handle edge cases', () => {
      expect(isValidEmail('@')).toBe(false);
      expect(isValidEmail('@@')).toBe(false);
      expect(isValidEmail('user@@example.com')).toBe(false);
    });
  });

  describe('integration scenarios', () => {
    it('should handle phone number workflow: detect -> validate -> normalize -> format', () => {
      const input = '12345678';

      // Detect
      expect(detectInputType(input)).toBe('phone');

      // Validate
      expect(isValidNorwegianPhone(input)).toBe(true);

      // Normalize to E.164
      const e164 = normalizePhoneToE164(input);
      expect(e164).toBe('+4712345678');

      // Format for display
      const display = formatPhoneForDisplay(e164);
      expect(display).toBe('123 45 678');
    });

    it('should handle email workflow: detect -> validate', () => {
      const input = 'user@example.com';

      // Detect
      expect(detectInputType(input)).toBe('email');

      // Validate
      expect(isValidEmail(input)).toBe(true);
    });

    it('should handle phone with spaces workflow', () => {
      const input = '12 345 678';

      // Detect (strips spaces)
      expect(detectInputType(input)).toBe('phone');

      // Validate (strips spaces)
      expect(isValidNorwegianPhone(input)).toBe(true);

      // Normalize (strips spaces)
      const e164 = normalizePhoneToE164(input);
      expect(e164).toBe('+4712345678');
    });

    it('should round-trip: 8-digit -> E.164 -> strip -> 8-digit', () => {
      const original = '12345678';
      const e164 = normalizePhoneToE164(original);
      const stripped = stripCountryCode(e164);
      expect(stripped).toBe(original);
    });

    it('should handle realistic user inputs', () => {
      // User enters phone with various spacing
      const inputs = [
        '12345678',
        '12 345 678',
        '123 456 78',
        '1234 5678',
        '  12345678  ',
      ];

      inputs.forEach(input => {
        expect(detectInputType(input)).toBe('phone');
        expect(isValidNorwegianPhone(input)).toBe(true);
        const normalized = normalizePhoneToE164(input);
        expect(normalized).toBe('+4712345678');
      });
    });
  });
});
