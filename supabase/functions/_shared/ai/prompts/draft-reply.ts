import type { NeutralSchema } from "../schema.ts";

export type DraftObjective = "reply" | "payment_reminder" | "follow_up" | "nudge";

export interface DraftInput {
  customerId: string;
  objective: DraftObjective;
  messages: { direction: string; body: string }[];
  customerName: string | null;
  outstandingAmount: number | null;
  enquiryContext: string | null;
}

export const draftReplySchema: NeutralSchema = {
  type: "object",
  properties: {
    message: { type: "string" },
    confidence: { type: "number" },
  },
  required: ["message", "confidence"],
};

export function draftReplyPrompt(input: DraftInput, sellerName: string): string {
  const lastMessages = input.messages.slice(-10);
  const chatLines = lastMessages
    .map((m) => `${m.direction === "inbound" ? "Customer" : "You"}: ${m.body}`)
    .join("\n");

  const objectiveInstructions: Record<DraftObjective, string> = {
    reply:
      "Write a warm, concise reply to the customer's latest message. Match the seller's conversational tone.",
    payment_reminder:
      "Write a polite payment reminder. Do NOT include any rupee amounts, UPI IDs, or account numbers in the message — those will be added by the seller from their records.",
    follow_up: "Write a friendly follow-up message to re-engage the customer.",
    nudge: "Write a short nudge to prompt the customer to respond.",
  };

  return [
    `You are drafting a WhatsApp message for an Indian seller named ${sellerName}.`,
    "Write in a friendly, natural Indian business tone (mix of English and simple Hindi is fine if appropriate).",
    "",
    "CRITICAL RULES:",
    "- NEVER include specific rupee amounts, UPI IDs, bank account numbers, or phone numbers in the message.",
    "- NEVER invent product details, prices, or order information not in the conversation.",
    "- Write prose only — the seller will add specific amounts from their records.",
    "- Keep it under 80 words.",
    "",
    `Objective: ${objectiveInstructions[input.objective]}`,
    "",
    "Recent conversation:",
    chatLines || "(No messages yet)",
    "",
    input.enquiryContext ? `Context: ${input.enquiryContext}` : "",
    "",
    "Return JSON with 'message' (the draft text) and 'confidence' (0..1, your confidence in the draft quality).",
  ].filter(Boolean).join("\n");
}
