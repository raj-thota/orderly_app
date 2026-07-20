import type { NeutralSchema } from "../schema.ts";

export const parseEnquirySchema: NeutralSchema = {
  type: "object",
  properties: {
    customer_name: { type: "string", nullable: true },
    phone: { type: "string", nullable: true },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          qty: { type: "integer" },
          price: { type: "number", nullable: true },
        },
        required: ["name", "qty"],
      },
    },
    intent: { type: "string", enum: ["inquiry", "order", "follow_up"] },
    follow_up_date: { type: "string", nullable: true },
    type: { type: "string", enum: ["enquiry", "order"] },
    confidence: { type: "number" },
    budget: { type: "number", nullable: true },
    notes: { type: "string", nullable: true },
  },
  required: ["items", "intent", "type", "confidence"],
};

export function parseEnquiryPrompt(text: string, todayIso: string): string {
  const hasText = text.trim().length > 0;
  return [
    "You extract structured sales-lead data from an Indian social-commerce",
    "seller's chat or spoken note. An image, if attached, is a screenshot of a",
    "chat — read the messages in it. Return ONLY data that is present or",
    "clearly implied. Use null when unsure; never invent a phone number or name.",
    "",
    "Rules:",
    "- phone: 10-digit Indian mobile if present, digits only, no country code.",
    "- items: product/qty pairs the customer wants; qty defaults to 1; price in",
    "  rupees as a number when stated, else null.",
    "- intent: 'order' if they are committing/booking/paying; 'follow_up' if they",
    "  want to be contacted later; otherwise 'inquiry'.",
    "- type: 'order' only when intent is 'order' AND there is at least one item;",
    "  otherwise 'enquiry'.",
    `- follow_up_date: absolute date (YYYY-MM-DD) resolved from today (${todayIso})`,
    "  when they mention a time like 'tomorrow'/'next week'; else null.",
    "- confidence: your overall 0..1 confidence in this extraction.",
    "- budget: the customer's stated maximum spend in rupees as a number, or null.",
    "- notes: any seller-useful context not captured elsewhere (e.g. colour preference,",
    "  delivery constraint, occasion); one short sentence or null.",
    "",
    hasText ? "Message:" : "Extract from the attached screenshot.",
    hasText ? text : "",
  ].join("\n");
}
