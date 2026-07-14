-- Capture v2 persists extracted budget and parse confidence on the lead.
alter table public.leads
  add column budget numeric(12,2) check (budget is null or budget >= 0),
  add column ai_confidence numeric(3,2)
    check (ai_confidence is null or (ai_confidence >= 0 and ai_confidence <= 1));
