-- Conversations (one thread per customer in V1) and messages.
-- Messages are immutable: select+insert policies only, no update/delete.
-- Backfill seeds one conversation per customer that has lead text, with the
-- lead message as the first inbound message (idempotent).

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, customer_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound')),
  source text not null check (source in ('paste','screenshot','voice','manual','ai_send')),
  body text not null,
  sent_at timestamptz,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create trigger trg_conversations_updated before update on public.conversations
  for each row execute function public.set_updated_at();

create index idx_messages_user_conv_time
  on public.messages (user_id, conversation_id, created_at);

-- FK-support index: avoids sequential scan on conversations during cascade delete.
create index idx_messages_conversation on public.messages (conversation_id);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy "own conversations" on public.conversations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own messages select" on public.messages
  for select using (auth.uid() = user_id);
create policy "own messages insert" on public.messages
  for insert with check (auth.uid() = user_id);

-- Defense-in-depth: remove anon schema discoverability (mirrors 0004 pattern).
revoke all on public.conversations from anon;
revoke all on public.messages from anon;

-- Backfill: conversation per (user, customer) that has at least one lead message.
insert into public.conversations (user_id, customer_id, last_message_at, created_at)
select l.user_id, l.customer_id, max(l.created_at), min(l.created_at)
from public.leads l
where l.customer_id is not null and coalesce(l.message, '') <> ''
group by l.user_id, l.customer_id
on conflict (user_id, customer_id) do nothing;

-- Backfill: each lead message becomes one inbound message.
insert into public.messages
  (user_id, conversation_id, direction, source, body, sent_at, created_at)
select l.user_id, c.id, 'inbound',
       case when l.source in ('paste','manual','screenshot') then l.source else 'paste' end,
       l.message, l.created_at, l.created_at
from public.leads l
join public.conversations c
  on c.user_id = l.user_id and c.customer_id = l.customer_id
where l.customer_id is not null
  and coalesce(l.message, '') <> ''
  and not exists (
    select 1 from public.messages m
    where m.conversation_id = c.id
      and m.body = l.message
      and m.created_at = l.created_at
  );
