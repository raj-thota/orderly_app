export interface ParseInput {
  text: string;
  image?: { mimeType: string; data: string }; // data = base64, no prefix
}

export interface ParsedEnquiry {
  customer_name: string | null;
  phone: string | null;
  items: { name: string; qty: number; price: number | null }[];
  intent: "inquiry" | "order" | "follow_up";
  follow_up_date: string | null; // ISO 8601 date (YYYY-MM-DD) or null
  type: "enquiry" | "order";
  confidence: number; // 0..1
}

// Gemini responseSchema (OpenAPI subset).
export const responseSchema = {
  type: "OBJECT",
  properties: {
    customer_name: { type: "STRING", nullable: true },
    phone: { type: "STRING", nullable: true },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: { type: "STRING" },
          qty: { type: "INTEGER" },
          price: { type: "NUMBER", nullable: true },
        },
        required: ["name", "qty"],
      },
    },
    intent: { type: "STRING", enum: ["inquiry", "order", "follow_up"] },
    follow_up_date: { type: "STRING", nullable: true },
    type: { type: "STRING", enum: ["enquiry", "order"] },
    confidence: { type: "NUMBER" },
  },
  required: ["items", "intent", "type", "confidence"],
};

export function buildPrompt(text: string, todayIso: string): string {
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
    "",
    hasText ? "Message:" : "Extract from the attached screenshot.",
    hasText ? text : "",
  ].join("\n");
}
