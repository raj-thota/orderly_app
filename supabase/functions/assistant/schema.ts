export interface AssistantInput {
  question: string;
  customer_id?: string;
  history?: Array<{ role: string; content: string }>;
}

export interface ProposedWorkItem {
  kind: string;
  customer_id: string;
  customer_name: string;
  draft_message: string;
  priority: "high" | "medium" | "low";
}

export interface AssistantOutput {
  answer: string;
  suggestions: string[];
  proposed_work_items: ProposedWorkItem[];
}

// Gemini function declarations for the 4 whitelisted read-only RPCs.
export const assistantTools = [
  {
    name: "outstanding_summary",
    description:
      "Returns a list of customers with outstanding (unpaid) amounts. Call this when asked about pending payments, money owed, or collections.",
    parameters: {
      type: "OBJECT",
      properties: {
        limit: {
          type: "INTEGER",
          description: "Max customers to return (default 10, max 20)",
        },
      },
      required: [],
    },
  },
  {
    name: "top_customers",
    description:
      "Returns the seller's top customers ranked by lifetime value. Call this for questions about best customers, highest revenue accounts, or repeat buyers.",
    parameters: {
      type: "OBJECT",
      properties: {
        limit: {
          type: "INTEGER",
          description: "Max customers to return (default 10, max 20)",
        },
      },
      required: [],
    },
  },
  {
    name: "pipeline_stats",
    description:
      "Returns aggregate business stats: total leads, open leads, total orders, active orders, total revenue, outstanding payments, paid this month, total customers. Call this for overview questions about the business.",
    parameters: {
      type: "OBJECT",
      properties: {},
      required: [],
    },
  },
  {
    name: "overdue_followups",
    description:
      "Returns follow-ups that are past their due date and not yet completed. Call this when asked about missed follow-ups, overdue tasks, or customers to contact.",
    parameters: {
      type: "OBJECT",
      properties: {
        limit: {
          type: "INTEGER",
          description: "Max follow-ups to return (default 10, max 20)",
        },
      },
      required: [],
    },
  },
];

export const finalResponseSchema = {
  type: "OBJECT",
  properties: {
    answer: {
      type: "STRING",
      description: "A concise, business-focused answer. No amounts, UPI IDs, or phone numbers — these come from the database, not from you. Reference customer names and factual info from the tool results.",
    },
    suggestions: {
      type: "ARRAY",
      items: { type: "STRING" },
      description: "2-4 short follow-up questions the seller might want to ask next.",
    },
    proposed_work_items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          kind: {
            type: "STRING",
            enum: ["payment_reminder", "reply", "follow_up", "create_order", "invoice"],
          },
          customer_id: { type: "STRING" },
          customer_name: { type: "STRING" },
          draft_message: {
            type: "STRING",
            description: "A short, polite message draft. MUST NOT contain phone numbers, UPI IDs, or exact rupee amounts.",
          },
          priority: { type: "STRING", enum: ["high", "medium", "low"] },
        },
        required: ["kind", "customer_id", "customer_name", "draft_message", "priority"],
      },
      description: "Work items to propose only when the user explicitly asks to create reminders or follow-ups. Empty otherwise.",
    },
  },
  required: ["answer", "suggestions", "proposed_work_items"],
};

export function buildSystemPrompt(sellerName: string): string {
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
