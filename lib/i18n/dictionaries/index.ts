/**
 * Dictionary exports and loader
 */

import type { Locale } from '../config';
import { no } from './no';
import { en } from './en';
import type { Dictionary } from './no';

type AppShellKey = 'common' | 'dateTime' | 'header' | 'footer' | 'userMenu' | 'navigation' | 'components';
export type AppNamespace =
  | 'pages.home'
  | 'pages.shifts'
  | 'pages.stats'
  | 'pages.settings'
  | 'pages.settings.subscription'
  | 'pages.auth'
  | 'onboarding';
export const APP_NAMESPACES: readonly AppNamespace[] = [
  'pages.home',
  'pages.shifts',
  'pages.stats',
  'pages.settings',
  'pages.settings.subscription',
  'pages.auth',
  'onboarding',
];

const dictionaries: Record<Locale, Dictionary> = {
  no,
  en,
};

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale] ?? dictionaries.no;
}

/**
 * Build a dictionary that only contains the app shell + selected namespaces.
 * This avoids serializing the entire site dictionary for every page.
 */
export function getAppDictionary(locale: Locale, namespaces: AppNamespace[] = []): Dictionary {
  const full = getDictionary(locale);

  const shellKeys: AppShellKey[] = ['common', 'dateTime', 'header', 'footer', 'userMenu', 'navigation', 'components'];
  const shell = shellKeys.reduce<Record<string, unknown>>((acc, key) => {
    acc[key] = full[key];
    return acc;
  }, {});

  const result: Record<string, unknown> = { ...shell };

  for (const namespace of namespaces) {
    const segments = namespace.split('.');
    let value: any = full;
    for (const segment of segments) {
      value = value?.[segment];
      if (value === undefined) break;
    }

    if (value !== undefined) {
      let cursor = result;
      segments.forEach((segment, index) => {
        if (index === segments.length - 1) {
          cursor[segment] = value;
        } else {
          cursor[segment] = cursor[segment] ?? {};
          cursor = cursor[segment] as Record<string, unknown>;
        }
      });
    }
  }

  return result as Dictionary;
}

export function getAppShellDictionary(locale: Locale): Dictionary {
  return getAppDictionary(locale, []);
}

export function getMarketingDictionary(locale: Locale): Pick<Dictionary, 'marketing' | 'legal'> {
  const full = getDictionary(locale);
  return {
    marketing: full.marketing,
    legal: full.legal,
  };
}

export function getAuthDictionary(locale: Locale): Dictionary {
  return getAppDictionary(locale, ['pages.auth']);
}
