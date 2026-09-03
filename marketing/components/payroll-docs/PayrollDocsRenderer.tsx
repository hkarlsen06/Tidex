interface PayrollDocsRendererProps {
  section: {
    id: string;
    title: string;
    subsections: Array<{
      heading?: string;
      paragraphs?: string[];
      list?: string[];
      code?: { language: string; content: string };
      note?: string;
      additionalCode?: { language: string; content: string };
      table?: { caption?: string; headers: string[]; rows: string[][] };
      steps?: Array<{
        title: string;
        paragraphs?: string[];
        list?: string[];
        code?: { language: string; content: string };
        note?: string;
      }>;
    }>;
  };
}

function isExampleText(text: string): boolean {
  return text.startsWith('Example:');
}

function CodeBlock({ content }: { content: string }) {
  return (
    <pre className="overflow-x-auto rounded-lg bg-[#1e1e1e] p-5 text-sm leading-relaxed text-[#d4d4d4] shadow-md sm:p-6">
      <code>{content}</code>
    </pre>
  );
}

export function PayrollDocsRenderer({ section }: PayrollDocsRendererProps) {
  return (
    <article>
      {/* Section Title */}
      <header className="mb-10 sm:mb-12">
        <h2 className="text-3xl font-bold text-text-primary sm:text-4xl">{section.title}</h2>
      </header>

      {/* Subsections */}
      <div className="divide-y divide-border-subtle">
        {section.subsections.map((subsection, idx) => {
          const isFirst = idx === 0;
          const isLast = idx === section.subsections.length - 1;
          return (
          <div
            key={idx}
            className={`space-y-5 ${
              isFirst && isLast ? '' : isFirst ? 'pb-6 sm:pb-8' : isLast ? 'pt-6 sm:pt-8' : 'py-6 sm:py-8'
            }`}
          >
            {/* Subsection Heading */}
            {subsection.heading && (
              <h3 className="text-xl font-semibold text-text-primary sm:text-2xl">
                {subsection.heading}
              </h3>
            )}

            {/* Paragraphs */}
            {subsection.paragraphs && subsection.paragraphs.length > 0 && (
              <div className="space-y-4">
                {subsection.paragraphs.map((para, pIdx) => {
                  const isExample = isExampleText(para);
                  return (
                    <p
                      key={pIdx}
                      className={`leading-relaxed ${
                        isExample
                          ? 'text-sm text-text-muted italic sm:text-base'
                          : 'text-base text-text-secondary sm:text-lg'
                      }`}
                    >
                      {para}
                    </p>
                  );
                })}
              </div>
            )}

            {/* List */}
            {subsection.list && subsection.list.length > 0 && (
              <ul className="ml-6 space-y-2 list-disc">
                {subsection.list.map((item, lIdx) => (
                  <li
                    key={lIdx}
                    className="text-base leading-relaxed text-text-secondary pl-2 sm:text-lg"
                  >
                    {item}
                  </li>
                ))}
              </ul>
            )}

            {/* Code Block */}
            {subsection.code && (
              <CodeBlock content={subsection.code.content} />
            )}

            {/* Note */}
            {subsection.note && (
              <p className="text-sm italic text-text-muted sm:text-base">{subsection.note}</p>
            )}

            {/* Additional Code Block */}
            {subsection.additionalCode && (
              <CodeBlock content={subsection.additionalCode.content} />
            )}

            {/* Table */}
            {subsection.table && (
              <figure className="overflow-hidden rounded-lg border border-border shadow-xs">
                {subsection.table.caption && (
                  <figcaption className="border-b border-border bg-surface-secondary px-4 py-3 text-sm font-medium text-text-muted sm:px-6">
                    {subsection.table.caption}
                  </figcaption>
                )}
                <div className="overflow-x-auto">
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
                        <tr
                          key={rIdx}
                          className="transition-colors hover:bg-surface-secondary/50"
                        >
                          {row.map((cell, cIdx) => (
                            <td
                              key={cIdx}
                              className="border-b border-border px-4 py-3 text-sm text-text-secondary sm:px-6 sm:py-4"
                            >
                              {cell}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </figure>
            )}

            {/* Steps (nested structure for algorithms) */}
            {subsection.steps && subsection.steps.length > 0 && (
              <div className="divide-y divide-border-subtle">
                {subsection.steps.map((step, sIdx) => {
                  const isFirstStep = sIdx === 0;
                  const isLastStep = sIdx === subsection.steps!.length - 1;
                  return (
                  <div key={sIdx} className={`border-l-2 border-border pl-6 space-y-4 ${
                    isFirstStep && isLastStep ? '' : isFirstStep ? 'pb-6 sm:pb-8' : isLastStep ? 'pt-6 sm:pt-8' : 'py-6 sm:py-8'
                  }`}>
                    <h4 className="text-lg font-medium text-text-primary sm:text-xl">
                      {step.title}
                    </h4>

                    {step.paragraphs && step.paragraphs.length > 0 && (
                      <div className="space-y-3">
                        {step.paragraphs.map((para, pIdx) => {
                          const isExample = isExampleText(para);
                          return (
                            <p
                              key={pIdx}
                              className={`leading-relaxed ${
                                isExample
                                  ? 'text-sm text-text-muted italic'
                                  : 'text-base text-text-secondary'
                              }`}
                            >
                              {para}
                            </p>
                          );
                        })}
                      </div>
                    )}

                    {step.list && step.list.length > 0 && (
                      <ul className="ml-6 space-y-2 list-disc">
                        {step.list.map((item, lIdx) => (
                          <li
                            key={lIdx}
                            className="text-base leading-relaxed text-text-secondary pl-2"
                          >
                            {item}
                          </li>
                        ))}
                      </ul>
                    )}

                    {step.code && (
                      <CodeBlock content={step.code.content} />
                    )}

                    {step.note && (
                      <p className="text-sm italic text-text-muted">{step.note}</p>
                    )}
                  </div>
                  );
                })}
              </div>
            )}
          </div>
          );
        })}
      </div>
    </article>
  );
}
