import type { NeutralSchema } from "../schema.ts";
import type { LlmTool } from "../types.ts";

export const assistantTools: LlmTool[] = [
  {
    name: "outstanding_summary",
    description:
      "Returns a list of customers with outstanding (unpaid) amounts. Call this when asked about pending payments, money owed, or collections.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max customers to return (default 10, max 20)" },
      },
    },
  },
  {
    name: "top_customers",
    description:
      "Returns the seller's top customers ranked by lifetime value. Call this for questions about best customers, highest revenue accounts, or repeat buyers.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max customers to return (default 10, max 20)" },
      },
    },
  },
  {
    name: "pipeline_stats",
    description:
      "Returns aggregate business stats: total leads, open leads, total orders, active orders, total revenue, outstanding payments, paid this month, total customers. Call this for overview questions about the business.",
    parameters: { type: "object", properties: {} },
  },
  {
    name: "overdue_followups",
    description:
      "Returns follow-ups that are past their due date and not yet completed. Call this when asked about missed follow-ups, overdue tasks, or customers to contact.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max follow-ups to return (default 10, max 20)" },
      },
    },
  },
];

export const assistantFinalSchema: NeutralSchema = {
  type: "object",
  properties: {
    answer: {
      type: "string",
      description:
        "A concise, business-focused answer. No amounts, UPI IDs, or phone numbers — these come from the database, not from you. Reference customer names and factual info from the tool results.",
    },
    suggestions: {
      type: "array",
      items: { type: "string" },
      description: "2-4 short follow-up questions the seller might want to ask next.",
    },
    proposed_work_items: {
      type: "array",
      description:
        "Work items to propose only when the user explicitly asks to create reminders or follow-ups. Empty otherwise.",
      items: {
        type: "object",
        properties: {
          kind: {
            type: "string",
            enum: ["payment_reminder", "reply", "follow_up", "create_order", "invoice"],
          },
          customer_id: { type: "string" },
          customer_name: { type: "string" },
          draft_message: {
            type: "string",
            description:
              "A short, polite message draft. MUST NOT contain phone numbers, UPI IDs, or exact rupee amounts.",
          },
          priority: { type: "string", enum: ["high", "medium", "low"] },
        },
        required: ["kind", "customer_id", "customer_name", "draft_message", "priority"],
      },
    },
  },
  required: ["answer", "suggestions", "proposed_work_items"],
};

export function assistantSystemPrompt(sellerName: string): string {
  return `You are the Closr AI assistant helping ${sellerName} manage their sales business.

You have access to read-only tools that fetch live data from the database. Use them to answer the seller's questions accurately.

CRITICAL RULES:
1. Never include phone numbers, UPI IDs, or Paytm/GPay handles in your answer or draft messages.
2. Never include exact rupee amounts in draft messages — refer to "the pending amount" or "the outstanding balance" instead.
3. Only propose work items (reminders, follow-ups) when the seller explicitly asks you to create them.
4. Keep answers concise and actionable. Reference actual customer names from tool results.
5. You are a business assistant, not a general chatbot. Stay focused on sales, payments, customers, and follow-ups.`;
}

// PII guard: reject proposed items whose draft_message leaks sensitive data.
export const PII_PATTERN = /₹|\d{10}|upi|@[a-z]|paytm|gpay|phonepe/i;
