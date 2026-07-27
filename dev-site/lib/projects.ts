import type { DevDictionary } from './dictionaries';

type ProjectCopy = DevDictionary['projects']['tidex'];

export interface DevProject {
  slug: string;
  copy: ProjectCopy;
  /** Accent CSS var name, sourced from the product's own app icon. */
  accent: string;
  icon: { src: string; alt: string };
  technologies: string[];
  links: { href: string; label: string }[];
}

export function getDevProjects(dictionary: DevDictionary): DevProject[] {
  const { projects } = dictionary;

  return [
    {
      slug: 'tidex',
      copy: projects.tidex,
      accent: '--accent-tidex',
      icon: { src: '/icons/tidex-app-icon.png', alt: 'Tidex app icon' },
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
        { href: 'https://tidex.no', label: `${projects.ctaVisit} tidex.no` },
      ],
    },
    {
      slug: 'paeonia',
      copy: projects.paeonia,
      accent: '--accent-paeonia',
      icon: { src: '/icons/paeonia-app-icon.png', alt: 'Paeonia app icon' },
      technologies: ['Swift', 'SwiftUI', 'SwiftData', 'Supabase', 'StoreKit 2', 'WidgetKit', 'Next.js'],
      links: [
        { href: 'https://apps.apple.com/app/paeonia/id6779833892', label: projects.ctaAppStore },
        { href: 'https://paeonia.no', label: `${projects.ctaVisit} paeonia.no` },
      ],
    },
    {
      slug: 'kvist',
      copy: projects.kvist,
      accent: '--accent-kvist',
      icon: { src: '/icons/kvist-app-icon.png', alt: 'Kvist app icon' },
      technologies: ['Swift', 'SwiftUI', 'macOS', 'Swift Package Manager', 'Git'],
      links: [{ href: 'https://github.com/kkarlsen06/Kvist', label: projects.ctaSource }],
    },
    {
      slug: 'lyriclint',
      copy: projects.lyriclint,
      accent: '--accent-lyriclint',
      icon: { src: '/icons/lyriclint-app-icon.svg', alt: 'LyricLint app icon' },
      technologies: ['SvelteKit', 'Svelte 5', 'TypeScript', 'CodeMirror 6', 'IndexedDB', 'Playwright'],
      links: [
        { href: 'https://lyriclint.com', label: `${projects.ctaVisit} lyriclint.com` },
        { href: 'https://github.com/kkarlsen06/LyricLint_for_Genius', label: projects.ctaSource },
      ],
    },
  ];
}

export function projectFeatures(copy: ProjectCopy) {
  return [copy.feature1, copy.feature2, copy.feature3, copy.feature4, copy.feature5, copy.feature6];
}
