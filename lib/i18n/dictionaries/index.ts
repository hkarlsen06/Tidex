/**
 * Dictionary exports and loader
 */

import type { Locale } from '../config';
import { no } from './no';
import { en } from './en';
import { de } from './de';
import type { Dictionary } from './no';

const dictionaries: Record<Locale, Dictionary> = {
  no,
  en,
  de,
};

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale] ?? dictionaries.no;
}
