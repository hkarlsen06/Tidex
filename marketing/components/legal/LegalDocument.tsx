import type { ReactNode } from 'react';
import type { Dictionary } from '@/lib/i18n/dictionaries';

interface LegalListItem {
  text: string;
  boldLabel?: string;
  link?: { href: string; text: string };
}

interface LegalSection {
  heading: string;
  paragraphs?: readonly string[];
  importantNote?: { label: string; text: string };
  listIntro?: string;
  list?: readonly LegalListItem[];
  subsections?: readonly { subheading: string; text: string }[];
  closingParagraph?: string;
}

interface LegalDocumentProps {
  content: Pick<Dictionary['legal']['terms' | 'privacy' | 'security'], 'title' | 'lastUpdatedDate' | 'lastUpdatedLabel' | 'dateLocale'> & {
    sections: readonly LegalSection[];
  };
  headerAction?: ReactNode;
}

export function LegalDocument({ content, headerAction }: LegalDocumentProps) {
  const formattedDate = new Date(content.lastUpdatedDate).toLocaleDateString(content.dateLocale);

  return (
    <div className="prose prose-sm max-w-none dark:prose-invert space-y-6">
      <div className="not-prose mb-2 flex flex-wrap items-start gap-3">
        <div>
          <h1 className="text-text-primary text-3xl font-semibold">{content.title}</h1>
          <p className="text-text-muted" suppressHydrationWarning>
            {content.lastUpdatedLabel}: {formattedDate}
          </p>
        </div>
        {headerAction && (
          <div className="shrink-0">
            {headerAction}
          </div>
        )}
      </div>

      {content.sections.map((section) => (
        <div key={section.heading}>
          <h2>{section.heading}</h2>
          {section.paragraphs?.map((paragraph, index) => (
            <p key={`${section.heading}-p-${index}`}>{paragraph}</p>
          ))}

          {section.importantNote && (
            <p>
              <strong>{section.importantNote.label}</strong> {section.importantNote.text}
            </p>
          )}

          {section.listIntro ? <p>{section.listIntro}</p> : null}

          {section.list && (
            <ul>
              {section.list.map((item, index) => (
                <li key={`${section.heading}-list-${index}`}>
                  {item.boldLabel && (
                    <>
                      <strong>{item.boldLabel}</strong>{' '}
                    </>
                  )}
                  {renderListText(item)}
                </li>
              ))}
            </ul>
          )}

          {section.subsections && (
            <div className="mt-4 space-y-3">
              {section.subsections.map((subsection, index) => (
                <div key={`${section.heading}-sub-${index}`}>
                  <h3 className="text-base font-semibold">{subsection.subheading}</h3>
                  <p>{subsection.text}</p>
                </div>
              ))}
            </div>
          )}

          {section.closingParagraph ? <p>{section.closingParagraph}</p> : null}
        </div>
      ))}
    </div>
  );
}

function renderListText(item: LegalListItem) {
  if (!item.link) {
    return item.text;
  }

  const [beforeLink = '', afterLink = ''] = item.text.split('{link}');

  return (
    <>
      {beforeLink}
      <a href={item.link.href} target="_blank" rel="noopener noreferrer">
        {item.link.text}
      </a>
      {afterLink}
    </>
  );
}
