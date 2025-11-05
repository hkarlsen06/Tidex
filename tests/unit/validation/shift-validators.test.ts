import { describe, it, expect } from 'vitest';
import { isISODate, isHHMM } from '@/lib/validation/shift-validators';

describe('shift-validators', () => {
  describe('isISODate', () => {
    it('should return true for valid ISO dates', () => {
      expect(isISODate('2025-01-15')).toBe(true);
      expect(isISODate('2024-12-31')).toBe(true);
      expect(isISODate('2023-06-01')).toBe(true);
    });

    it('should return false for invalid ISO dates', () => {
      expect(isISODate('2025-1-5')).toBe(false);
      expect(isISODate('15-01-2025')).toBe(false);
      expect(isISODate('2025/01/15')).toBe(false);
      expect(isISODate('01-15-2025')).toBe(false);
    });

    it('should return false for non-date strings', () => {
      expect(isISODate('')).toBe(false);
      expect(isISODate('not a date')).toBe(false);
      // Note: isISODate only checks format, not validity of month/day values
    });

    it('should return false for dates with incorrect separators', () => {
      expect(isISODate('2025.01.15')).toBe(false);
      expect(isISODate('2025 01 15')).toBe(false);
    });
  });

  describe('isHHMM', () => {
    it('should return true for valid HH:MM times', () => {
      expect(isHHMM('09:30')).toBe(true);
      expect(isHHMM('00:00')).toBe(true);
      expect(isHHMM('23:59')).toBe(true);
      expect(isHHMM('12:00')).toBe(true);
    });

    it('should return false for invalid HH:MM times', () => {
      expect(isHHMM('9:30')).toBe(false);
      expect(isHHMM('09:3')).toBe(false);
      expect(isHHMM('9:3')).toBe(false);
    });

    it('should return false for non-time strings', () => {
      expect(isHHMM('')).toBe(false);
      expect(isHHMM('not a time')).toBe(false);
      // Note: isHHMM only checks format, not validity of hour/minute values
    });

    it('should return false for times with incorrect separators', () => {
      expect(isHHMM('09.30')).toBe(false);
      expect(isHHMM('09-30')).toBe(false);
      expect(isHHMM('09 30')).toBe(false);
    });
  });
});
