import type { Dictionary } from '@/lib/i18n/dictionaries/no';

type SecurityContent = Dictionary['legal']['security'];

interface SecurityPolicyProps {
  content: SecurityContent;
}

export function SecurityPolicy({ content }: SecurityPolicyProps) {
  const formattedDate = new Date(content.lastUpdatedDate).toLocaleDateString(content.dateLocale);

  return (
    <div className="prose prose-sm max-w-none dark:prose-invert space-y-6">
      <div>
        <h1>{content.title}</h1>
        <p className="text-text-muted" suppressHydrationWarning>
          {content.lastUpdatedLabel}: {formattedDate}
        </p>
      </div>

      {content.sections.map((section) => (
        <div key={section.heading}>
          <h2>{section.heading}</h2>
          {'paragraphs' in section && section.paragraphs && (section.paragraphs as unknown as readonly string[]).map((paragraph, index) => (
            <p key={`${section.heading}-p-${index}`}>{paragraph}</p>
          ))}

          {'importantNote' in section && section.importantNote ? (
            <p>
              <strong>{(section.importantNote as any).label}</strong> {(section.importantNote as any).text}
            </p>
          ) : null}

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
