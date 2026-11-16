-- Line Manager cloud mirror.
-- SECURITY: each installation signs in anonymously and receives its own auth.uid().
-- Enable Anonymous Sign-Ins in Supabase Authentication settings before enabling sync.
-- Never create public/anon policies with USING (true) for customer/payment data.

create extension if not exists pgcrypto;

create table if not exists public.customers (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  name text not null,
  phone text,
  whatsapp text,
  address text,
  notes text,
  registered_at timestamptz,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.packages (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  name text not null,
  price_piasters bigint not null check (price_piasters >= 0),
  description text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (owner_id, name)
);

create table if not exists public.package_price_history (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  package_id uuid not null references public.packages(id),
  old_price_piasters bigint not null,
  new_price_piasters bigint not null,
  effective_year int not null,
  effective_month int not null check (effective_month between 1 and 12),
  created_at timestamptz not null default now()
);

create table if not exists public.lines (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  customer_id uuid not null references public.customers(id),
  package_id uuid not null references public.packages(id),
  number text not null,
  carrier text not null default 'Orange',
  line_type text not null default 'calls',
  owner_name text,
  start_year int,
  start_month int,
  status text not null default 'active',
  notes text,
  credit_piasters bigint not null default 0 check (credit_piasters >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  stopped_at timestamptz,
  unique (owner_id, number)
);

create table if not exists public.billing_cycles (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  line_id uuid not null references public.lines(id),
  year int not null,
  month int not null check (month between 1 and 12),
  price_piasters bigint not null check (price_piasters >= 0),
  package_name_snapshot text not null,
  paid_piasters bigint not null default 0 check (paid_piasters >= 0),
  status text not null default 'unpaid',
  unique (line_id, year, month)
);

create table if not exists public.payments (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  line_id uuid not null references public.lines(id),
  customer_id uuid not null references public.customers(id),
  amount_piasters bigint not null check (amount_piasters > 0),
  paid_at timestamptz not null,
  method text not null default 'cash',
  reference text,
  idempotency_key text,
  notes text,
  collector_name text not null default 'ماما',
  receipt_number text not null,
  is_voided boolean not null default false,
  created_at timestamptz not null default now(),
  unique (owner_id, receipt_number)
);

create table if not exists public.payment_allocations (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  payment_id uuid not null references public.payments(id),
  billing_cycle_id uuid not null references public.billing_cycles(id),
  amount_piasters bigint not null check (amount_piasters > 0),
  unique (payment_id, billing_cycle_id)
);

create table if not exists public.expenses (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  title text not null,
  amount_piasters bigint not null check (amount_piasters > 0),
  spent_at timestamptz not null,
  category text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key,
  owner_id uuid not null default auth.uid(),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  old_value text,
  new_value text,
  created_at timestamptz not null default now()
);

-- Backward-compatible column additions MUST run before indexes and policies.
-- Existing rows in an older cloud database keep owner_id = NULL until the owner
-- explicitly migrates them; they remain inaccessible under the RLS policy.
alter table public.customers add column if not exists owner_id uuid default auth.uid();
alter table public.customers add column if not exists phone text;
alter table public.customers add column if not exists whatsapp text;
alter table public.customers add column if not exists address text;
alter table public.customers add column if not exists notes text;
alter table public.customers add column if not exists registered_at timestamptz;
alter table public.customers add column if not exists is_archived boolean not null default false;
alter table public.customers add column if not exists created_at timestamptz not null default now();
alter table public.customers add column if not exists updated_at timestamptz not null default now();
alter table public.customers add column if not exists deleted_at timestamptz;

alter table public.packages add column if not exists owner_id uuid default auth.uid();
alter table public.packages add column if not exists description text;
alter table public.packages add column if not exists is_archived boolean not null default false;
alter table public.packages add column if not exists created_at timestamptz not null default now();
alter table public.packages add column if not exists updated_at timestamptz not null default now();
alter table public.packages add column if not exists deleted_at timestamptz;

alter table public.package_price_history add column if not exists owner_id uuid default auth.uid();
alter table public.package_price_history add column if not exists created_at timestamptz not null default now();

alter table public.lines add column if not exists owner_id uuid default auth.uid();
alter table public.lines add column if not exists carrier text not null default 'Orange';
alter table public.lines add column if not exists line_type text not null default 'calls';
alter table public.lines add column if not exists owner_name text;
alter table public.lines add column if not exists start_year int;
alter table public.lines add column if not exists start_month int;
alter table public.lines add column if not exists status text not null default 'active';
alter table public.lines add column if not exists notes text;
alter table public.lines add column if not exists credit_piasters bigint not null default 0;
alter table public.lines add column if not exists created_at timestamptz not null default now();
alter table public.lines add column if not exists updated_at timestamptz not null default now();
alter table public.lines add column if not exists deleted_at timestamptz;
alter table public.lines add column if not exists stopped_at timestamptz;

alter table public.billing_cycles add column if not exists owner_id uuid default auth.uid();
alter table public.billing_cycles add column if not exists package_name_snapshot text not null default '';
alter table public.billing_cycles add column if not exists paid_piasters bigint not null default 0;
alter table public.billing_cycles add column if not exists status text not null default 'unpaid';

alter table public.payments add column if not exists owner_id uuid default auth.uid();
alter table public.payments add column if not exists method text not null default 'cash';
alter table public.payments add column if not exists reference text;
alter table public.payments add column if not exists idempotency_key text;
alter table public.payments add column if not exists notes text;
alter table public.payments add column if not exists collector_name text not null default 'ماما';
alter table public.payments add column if not exists is_voided boolean not null default false;
alter table public.payments add column if not exists created_at timestamptz not null default now();

alter table public.payment_allocations add column if not exists owner_id uuid default auth.uid();
alter table public.expenses add column if not exists owner_id uuid default auth.uid();
alter table public.expenses add column if not exists category text;
alter table public.expenses add column if not exists notes text;
alter table public.expenses add column if not exists created_at timestamptz not null default now();
alter table public.audit_logs add column if not exists owner_id uuid default auth.uid();
alter table public.audit_logs add column if not exists created_at timestamptz not null default now();

-- Set defaults for newly inserted rows in older databases as well.
alter table public.customers alter column owner_id set default auth.uid();
alter table public.packages alter column owner_id set default auth.uid();
alter table public.package_price_history alter column owner_id set default auth.uid();
alter table public.lines alter column owner_id set default auth.uid();
alter table public.billing_cycles alter column owner_id set default auth.uid();
alter table public.payments alter column owner_id set default auth.uid();
alter table public.payment_allocations alter column owner_id set default auth.uid();
alter table public.expenses alter column owner_id set default auth.uid();
alter table public.audit_logs alter column owner_id set default auth.uid();

-- Indexes are deliberately created only after owner_id migrations above.
create index if not exists idx_customers_owner_name on public.customers(owner_id, name);
create index if not exists idx_customers_owner_phone on public.customers(owner_id, phone);
create index if not exists idx_lines_owner_number on public.lines(owner_id, number);
create index if not exists idx_lines_customer on public.lines(customer_id);
create index if not exists idx_cycles_line_month on public.billing_cycles(line_id, year, month);
create index if not exists idx_payments_line_date on public.payments(line_id, paid_at);
create index if not exists idx_payments_owner_receipt on public.payments(owner_id, receipt_number);
create unique index if not exists idx_payments_owner_idempotency
  on public.payments(owner_id, idempotency_key)
  where idempotency_key is not null;

-- Keep all business rows scoped to the authenticated installation owner.
do $$
declare t text;
begin
  foreach t in array array['customers','packages','package_price_history','lines','billing_cycles','payments','payment_allocations','expenses','audit_logs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "owner_access" on public.%I', t);
    execute format(
      'create policy "owner_access" on public.%I for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid())',
      t
    );
  end loop;
end $$;

grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on public.customers, public.packages, public.package_price_history,
  public.lines, public.billing_cycles, public.payments,
  public.payment_allocations, public.expenses, public.audit_logs from anon;
