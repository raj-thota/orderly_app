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
