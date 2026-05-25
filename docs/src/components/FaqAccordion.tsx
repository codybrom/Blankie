import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

export interface FaqItem {
  question: string;
  /** Pre-rendered (marked) HTML for the answer. */
  answerHtml: string;
}

/**
 * FAQ rendered as a shadcn/Base UI Accordion. Answers are marked-rendered HTML,
 * injected via dangerouslySetInnerHTML and styled by the global `.faq-details`
 * rules. `multiple` preserves the prior `<details>` behavior (independently open).
 */
export function FaqAccordion({ items }: { items: FaqItem[] }) {
  return (
    <Accordion multiple className="flex flex-col gap-4">
      {items.map((item, i) => (
        <AccordionItem
          key={i}
          value={`faq-${i}`}
          className="rounded-lg border-none bg-dark-gray transition-colors hover:bg-zinc-800"
        >
          <AccordionTrigger className="cursor-pointer items-center gap-1.5 px-4 py-3 text-lg font-medium text-gray-100 hover:no-underline">
            {item.question}
          </AccordionTrigger>
          <AccordionContent className="px-4 text-gray-200">
            <div
              className="faq-details"
              dangerouslySetInnerHTML={{ __html: item.answerHtml }}
            />
          </AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  );
}
