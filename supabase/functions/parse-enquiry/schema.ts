export interface ParsedEnquiry {
  customer_name: string | null;
  phone: string | null;
  items: { name: string; qty: number; price: number | null }[];
  intent: "inquiry" | "order" | "follow_up";
  follow_up_date: string | null;
  type: "enquiry" | "order";
  confidence: number;
  budget: number | null;
  notes: string | null;
}
