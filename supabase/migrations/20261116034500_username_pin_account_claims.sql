create table if not exists public.account_claims (
  username_key text primary key check (char_length(username_key) between 1 and 64),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.account_claims enable row level security;
revoke all on public.account_claims from anon, authenticated;
grant all on public.account_claims to service_role;
