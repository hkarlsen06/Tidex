import type { ReactNode } from 'react';
import type { Dictionary } from '@/lib/i18n/dictionaries';

type TermsContent = Dictionary['legal']['terms'];

interface TermsOfServiceProps {
  content: TermsContent;
  headerAction?: ReactNode;
}

export function TermsOfService({ content, headerAction }: TermsOfServiceProps) {
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
          {'paragraphs' in section && section.paragraphs && (section.paragraphs as unknown as readonly string[]).map((paragraph, index) => (
            <p key={`${section.heading}-p-${index}`}>{paragraph}</p>
          ))}

          {'importantNote' in section && section.importantNote && (
            <p>
              <strong>{(section.importantNote as any).label}</strong> {(section.importantNote as any).text}
            </p>
          )}

          {'listIntro' in section && section.listIntro ? <p>{String(section.listIntro)}</p> : null}

          {'list' in section && section.list && (
            <ul>
              {(section.list as unknown as any[]).map((item, index) => (
                <li key={`${section.heading}-list-${index}`}>
                  {'boldLabel' in item && item.boldLabel && (
                    <>
                      <strong>{item.boldLabel as string}</strong>{' '}
                    </>
                  )}
                  {renderListText(item)}
                </li>
              ))}
            </ul>
          )}

          {'subsections' in section && section.subsections && (
            <div className="mt-4 space-y-3">
              {(section.subsections as unknown as any[]).map((subsection, index) => (
                <div key={`${section.heading}-sub-${index}`}>
                  <h3 className="text-base font-semibold">{subsection.subheading}</h3>
                  <p>{subsection.text}</p>
                </div>
              ))}
            </div>
          )}

          {'closingParagraph' in section && section.closingParagraph ? <p>{String(section.closingParagraph)}</p> : null}
        </div>
      ))}
    </div>
  );
}

function renderListText(item: any) {
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
