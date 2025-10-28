'use client';

import { Light as SyntaxHighlighter } from 'react-syntax-highlighter';
import typescript from 'react-syntax-highlighter/dist/esm/languages/hljs/typescript';
import { vs2015 } from 'react-syntax-highlighter/dist/esm/styles/hljs';

// Register only the languages we need
SyntaxHighlighter.registerLanguage('typescript', typescript);

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

// Helper to determine if a heading should have extra spacing above it
function shouldHaveExtraSpacing(heading: string): boolean {
  // Patterns that should have extra spacing (they mark new sections/items):
  // - Numbered items: "1.", "2.", "3.", "4."
  // - Method labels: "Method 1:", "Method 2:", "Method 3:"
  // - Step labels: "Step 1:", "Step 2:", "Step 3:", "Step 4:"
  // - Named sections that follow intro sections

  // Check for numbered/labeled headings
  if (/^(\d+\.|Method \d+:|Step \d+:)/.test(heading)) {
    return true;
  }

  // Specific headings that introduce new concepts and should have spacing
  const spacedHeadings = [
    'The algorithm',
    'Supplement rules',
    'Preset supplement rules',
    'Custom supplements',
    'Overlapping supplements',
    'Source code',
    'Default settings',
    'Threshold',
    'Break audit',
    'Precision',
    'Example: Evening shift with night supplement',
    'Complete example: Saturday evening',
  ];

  return spacedHeadings.includes(heading);
}

// Helper to check if heading is introductory (no extra spacing needed)
function isIntroductoryHeading(heading: string): boolean {
  const introHeadings = [
    'How we resolve the hourly rate',
    'How shifts become wage periods',
    'How evening, night, and weekend pay is applied',
    'Automatic break deductions',
    'From database to UI',
    'Transparency by design',
    'What this guide covers',
    'Architecture highlights',
  ];

  return introHeadings.includes(heading);
}

// Helper to check if a paragraph is an example
function isExampleText(text: string): boolean {
  return text.startsWith('Example:');
}

export function PayrollDocsRenderer({ section }: PayrollDocsRendererProps) {
  return (
    <article className="space-y-12">
      {/* Section Title */}
      <header>
        <h2 className="text-3xl font-bold text-text-primary sm:text-4xl">{section.title}</h2>
      </header>

      {/* Subsections */}
      <div className="space-y-14">
        {section.subsections.map((subsection, idx) => {
          const isFirstSubsection = idx === 0;
          const needsExtraSpacing =
            subsection.heading &&
            !isFirstSubsection &&
            !isIntroductoryHeading(subsection.heading) &&
            shouldHaveExtraSpacing(subsection.heading);

          return (
            <div key={idx} className="space-y-6">
              {/* Subsection Heading */}
              {subsection.heading && (
                <h3
                  className={`text-xl font-semibold text-text-primary sm:text-2xl ${
                    needsExtraSpacing ? 'pt-8' : ''
                  }`}
                >
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
                  <li key={lIdx} className="text-base leading-relaxed text-text-secondary sm:text-lg pl-2">
                    {item}
                  </li>
                ))}
              </ul>
            )}

            {/* Code Block */}
            {subsection.code && (
              <div className="overflow-hidden rounded-lg shadow-md">
                <SyntaxHighlighter
                  language={subsection.code.language}
                  style={vs2015}
                  customStyle={{
                    margin: 0,
                    padding: '1.5rem',
                    fontSize: '0.875rem',
                    borderRadius: '0.5rem',
                    lineHeight: '1.6',
                  }}
                >
                  {subsection.code.content}
                </SyntaxHighlighter>
              </div>
            )}

            {/* Note */}
            {subsection.note && (
              <p className="text-sm italic text-text-muted sm:text-base">{subsection.note}</p>
            )}

            {/* Additional Code Block */}
            {subsection.additionalCode && (
              <div className="overflow-hidden rounded-lg shadow-md">
                <SyntaxHighlighter
                  language={subsection.additionalCode.language}
                  style={vs2015}
                  customStyle={{
                    margin: 0,
                    padding: '1.5rem',
                    fontSize: '0.875rem',
                    borderRadius: '0.5rem',
                    lineHeight: '1.6',
                  }}
                >
                  {subsection.additionalCode.content}
                </SyntaxHighlighter>
              </div>
            )}

            {/* Table */}
            {subsection.table && (
              <figure className="space-y-3">
                {subsection.table.caption && (
                  <figcaption className="text-base font-medium text-text-primary sm:text-lg">
                    {subsection.table.caption}
                  </figcaption>
                )}
                <div className="overflow-x-auto rounded-lg border border-border shadow-sm">
                  <table className="w-full border-collapse">
                    <thead>
                      <tr className="bg-surface-secondary">
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
              <div className="space-y-8">
                {subsection.steps.map((step, sIdx) => (
                  <div key={sIdx} className="border-l-2 border-border pl-6 space-y-4">
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
                          <li key={lIdx} className="text-base leading-relaxed text-text-secondary pl-2">
                            {item}
                          </li>
                        ))}
                      </ul>
                    )}

                    {step.code && (
                      <div className="overflow-hidden rounded-lg shadow-md">
                        <SyntaxHighlighter
                          language={step.code.language}
                          style={vs2015}
                          customStyle={{
                            margin: 0,
                            padding: '1.25rem',
                            fontSize: '0.875rem',
                            borderRadius: '0.5rem',
                            lineHeight: '1.6',
                          }}
                        >
                          {step.code.content}
                        </SyntaxHighlighter>
                      </div>
                    )}

                    {step.note && (
                      <p className="text-sm italic text-text-muted">{step.note}</p>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
          );
        })}
      </div>
    </article>
  );
}
