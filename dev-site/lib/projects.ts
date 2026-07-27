import type { DevDictionary } from './dictionaries';
import type { DevLocale } from './i18n-config';

type ProjectCopy = DevDictionary['projects']['tidex'];

export interface DevProject {
  slug: string;
  copy: ProjectCopy;
  /** Accent CSS var name, sourced from the product's own app icon. */
  accent: string;
  icon: { src: string; alt: string };
  /**
   * True when the icon file is a full-bleed square and needs to be clipped into an
   * app-icon shape. Paeonia and Kvist already ship their own rounded silhouette with
   * transparent corners, so framing them would shave their real edge.
   */
  iconIsSquare: boolean;
  technologies: string[];
  links: { href: string; label: string }[];
}

export function getDevProjects(dictionary: DevDictionary, locale: DevLocale): DevProject[] {
  const { projects } = dictionary;

  return [
    {
      slug: 'tidex',
      copy: projects.tidex,
      accent: '--accent-tidex',
      icon: { src: '/icons/tidex-app-icon.png', alt: 'Tidex app icon' },
      iconIsSquare: true,
      technologies: [
        'Swift',
        'SwiftUI',
        'SwiftData',
        'Supabase',
        'StoreKit 2',
        'WidgetKit',
        'ActivityKit',
        'watchOS',
        'Next.js',
      ],
      links: [
        { href: 'https://apps.apple.com/app/tidex/id6757129790', label: projects.ctaAppStore },
        { href: `https://tidex.no/${locale}/`, label: `${projects.ctaVisit} tidex.no` },
      ],
    },
    {
      slug: 'paeonia',
      copy: projects.paeonia,
      accent: '--accent-paeonia',
      icon: { src: '/icons/paeonia-app-icon.png', alt: 'Paeonia app icon' },
      iconIsSquare: false,
      technologies: ['Swift', 'SwiftUI', 'SwiftData', 'Supabase', 'StoreKit 2', 'WidgetKit', 'Next.js'],
      // Not on the App Store yet, so the product site is the only destination.
      links: [{ href: `https://paeonia.no/${locale}/`, label: `${projects.ctaVisit} paeonia.no` }],
    },
    {
      slug: 'kvist',
      copy: projects.kvist,
      accent: '--accent-kvist',
      icon: { src: '/icons/kvist-app-icon.png', alt: 'Kvist app icon' },
      iconIsSquare: false,
      technologies: ['Swift', 'SwiftUI', 'macOS', 'Swift Package Manager', 'Git'],
      links: [{ href: 'https://github.com/hkarlsen06/Kvist', label: projects.ctaSource }],
    },
    {
      slug: 'lyriclint',
      copy: projects.lyriclint,
      accent: '--accent-lyriclint',
      icon: { src: '/icons/lyriclint-app-icon.svg', alt: 'LyricLint app icon' },
      iconIsSquare: true,
      technologies: ['SvelteKit', 'Svelte 5', 'TypeScript', 'CodeMirror 6', 'IndexedDB', 'Playwright'],
      links: [
        { href: 'https://lyriclint.com', label: `${projects.ctaVisit} lyriclint.com` },
        { href: 'https://github.com/hkarlsen06/LyricLint_for_Genius', label: projects.ctaSource },
      ],
    },
  ];
}

export function projectFeatures(copy: ProjectCopy) {
  return [copy.feature1, copy.feature2, copy.feature3, copy.feature4, copy.feature5, copy.feature6];
}
