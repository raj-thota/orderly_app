export interface SummarizeInput {
  customerName: string | null;
  messages: { direction: string; body: string; id: string }[];
  existingFacts: { fact: string }[];
}

export interface SummarizeOutput {
  bullets: string[];
  close_confidence: number;
  facts: { fact: string; source_message_id: string }[];
}

export const responseSchema = {
  type: "OBJECT",
  properties: {
    bullets: {
      type: "ARRAY",
      items: { type: "STRING" },
    },
    close_confidence: { type: "NUMBER" },
    facts: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          fact: { type: "STRING" },
          source_message_id: { type: "STRING" },
        },
        required: ["fact", "source_message_id"],
      },
    },
  },
  required: ["bullets", "close_confidence", "facts"],
};

export function buildPrompt(input: SummarizeInput): string {
  const chatLines = input.messages
    .map((m) => `[${m.id}] ${m.direction === "inbound" ? "Customer" : "Seller"}: ${m.body}`)
    .join("\n");

  return [
    "You summarize a seller-customer WhatsApp conversation for an Indian social-commerce seller.",
    "",
    "CRITICAL RULES:",
    "- NEVER include rupee amounts, phone numbers, UPI IDs, or payment details in your output.",
    "- Bullets describe the customer's interests, preferences, and intent — not financial specifics.",
    "- facts are standalone insights useful for future interactions (preferences, occasions, tone).",
    "- Source_message_id must be an exact ID from the conversation below.",
    "",
    `Customer name: ${input.customerName ?? "Unknown"}`,
    "",
    "Conversation (format: [message_id] Sender: body):",
    chatLines || "(No messages)",
    "",
    "Return JSON with:",
    "- bullets: 2-5 short bullet points summarising this customer's interests and status",
    "- close_confidence: 0..1 probability this lead will convert to an order soon",
    "- facts: reusable facts about the customer (max 5, only novel ones not already known)",
  ].join("\n");
}
