/**
 * Dictionary exports and loader
 */

import type { Locale } from '../config';
import { no } from './no';
import { en } from './en';
import type { Dictionary } from './no';

const dictionaries: Record<Locale, Dictionary> = {
  no,
  en,
};

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale] ?? dictionaries.no;
}
