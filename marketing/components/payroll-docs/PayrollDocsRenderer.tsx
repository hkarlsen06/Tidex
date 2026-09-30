export interface PayrollDocsSubsection {
  heading?: string;
  paragraphs?: string[];
  list?: string[];
  /** Render `list` as a numbered list. */
  ordered?: boolean;
  table?: { headers: string[]; rows: string[][] };
  code?: string;
  note?: string;
}

export interface PayrollDocsSection {
  id: string;
  title: string;
  /** One-sentence answer shown under the section title. */
  summary: string;
  subsections: PayrollDocsSubsection[];
}

/** Renders `backtick` spans as inline code. */
function Inline({ text }: { text: string }) {
  return (
    <>
      {text.split('`').map((part, index) =>
        index % 2 === 1 ? (
          <code
            key={index}
            className="rounded bg-surface-secondary px-1.5 py-0.5 font-mono text-[0.9em] text-text-primary"
          >
            {part}
          </code>
        ) : (
          part
        ),
      )}
    </>
  );
}

function CodeBlock({ content }: { content: string }) {
  return (
    <pre className="overflow-x-auto rounded-lg bg-[#1e1e1e] p-5 text-sm leading-relaxed text-[#d4d4d4] shadow-md sm:p-6">
      <code>{content}</code>
    </pre>
  );
}

export function PayrollDocsRenderer({ section }: { section: PayrollDocsSection }) {
  return (
    <article>
      <header className="mb-8 space-y-4 sm:mb-10">
        <h2 className="text-3xl font-bold text-text-primary sm:text-4xl">{section.title}</h2>
        <p className="max-w-3xl rounded-lg border-l-4 border-brand-gradient-start bg-surface-secondary px-5 py-4 text-base font-medium leading-relaxed text-text-primary sm:text-lg">
          <Inline text={section.summary} />
        </p>
      </header>

      <div className="divide-y divide-border-subtle">
        {section.subsections.map((subsection, idx) => {
          const isFirst = idx === 0;
          const isLast = idx === section.subsections.length - 1;
          const ListTag = subsection.ordered ? 'ol' : 'ul';
          return (
            <div
              key={idx}
              className={`space-y-5 ${
                isFirst && isLast ? '' : isFirst ? 'pb-6 sm:pb-8' : isLast ? 'pt-6 sm:pt-8' : 'py-6 sm:py-8'
              }`}
            >
              {subsection.heading && (
                <h3 className="text-xl font-semibold text-text-primary sm:text-2xl">
                  <Inline text={subsection.heading} />
                </h3>
              )}

              {subsection.paragraphs?.map((para, pIdx) => (
                <p key={pIdx} className="text-base leading-relaxed text-text-secondary sm:text-lg">
                  <Inline text={para} />
                </p>
              ))}

              {subsection.list && subsection.list.length > 0 && (
                <ListTag
                  className={`ml-6 space-y-2 ${subsection.ordered ? 'list-decimal' : 'list-disc'}`}
                >
                  {subsection.list.map((item, lIdx) => (
                    <li
                      key={lIdx}
                      className="pl-2 text-base leading-relaxed text-text-secondary sm:text-lg"
                    >
                      <Inline text={item} />
                    </li>
                  ))}
                </ListTag>
              )}

              {subsection.table && (
                <div className="overflow-x-auto rounded-lg border border-border shadow-xs">
                  <table className="w-full border-collapse">
                    <thead>
                      <tr className="bg-surface-secondary/50">
                        {subsection.table.headers.map((header, hIdx) => (
                          <th
                            key={hIdx}
                            className="border-b border-border px-4 py-3 text-left text-sm font-semibold text-text-primary sm:px-6 sm:py-4"
                          >
                            {header}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {subsection.table.rows.map((row, rIdx) => (
                        <tr key={rIdx} className="transition-colors hover:bg-surface-secondary/50">
                          {row.map((cell, cIdx) => (
                            <td
                              key={cIdx}
                              className={`border-b border-border px-4 py-3 align-top text-sm sm:px-6 sm:py-4 ${
                                cIdx === 0 ? 'font-medium text-text-primary' : 'text-text-secondary'
                              }`}
                            >
                              <Inline text={cell} />
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              {subsection.code && <CodeBlock content={subsection.code} />}

              {subsection.note && (
                <p className="text-sm leading-relaxed text-text-muted sm:text-base">
                  <Inline text={subsection.note} />
                </p>
              )}
            </div>
          );
        })}
      </div>
    </article>
  );
}
