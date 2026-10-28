-- ============================================================
-- Jugan Gym - Supabase schema
-- Run this whole file once in: Supabase Dashboard > SQL Editor
-- ============================================================

-- ---------- ADMIN CHECK ----------
-- Same admin email as kAdminEmails in lib/main.dart.
-- IMPORTANT: keep "Confirm email" ENABLED in Authentication settings so nobody
-- can sign up with the admin email without owning it.
create or replace function public.is_admin()
returns boolean language sql stable as $$
  select lower(coalesce(auth.jwt() ->> 'email', ''))
         = any (array['kingbaldo34@gmail.com']);
$$;

-- ---------- TABLES ----------
create table if not exists public.products (
  id           text primary key,
  name         text not null,
  description  text not null default '',
  brand        text not null default '',
  category     text not null default 'equipment',
  price        numeric(12,2) not null check (price >= 0),
  stock        integer not null default 0 check (stock >= 0),
  low_stock_at integer not null default 5,
  visible      boolean not null default true,
  updated_at   timestamptz not null default now()
);

create table if not exists public.orders (
  id                   text primary key,
  user_id              uuid not null default auth.uid() references auth.users(id),
  user_email           text,
  customer_name        text not null,
  phone                text not null,
  address              text not null,
  items                jsonb not null,
  item_count           integer not null,
  total_price          numeric(12,2) not null,
  currency             text not null default '₱',
  payment_method       text not null,            -- 'cod' | 'xendit'
  payment_status       text not null,            -- pay_on_delivery | unpaid | paid | expired
  status               text not null,            -- placed | awaiting_payment | completed | cancelled
  xendit_invoice_id    text,
  xendit_invoice_url   text,
  date                 text not null,
  created_at           timestamptz not null default now()
);
create index if not exists orders_user_idx on public.orders(user_id);

-- Per-user saved results (protein, body, workouts)
create table if not exists public.user_records (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id),
  collection  text not null,
  data        jsonb not null default '{}'::jsonb,
  saved_at    timestamptz not null default now()
);
create index if not exists user_records_idx on public.user_records(user_id, collection);

-- ---------- ROW LEVEL SECURITY ----------
alter table public.products     enable row level security;
alter table public.orders       enable row level security;
alter table public.user_records enable row level security;

-- products: customers see visible items, admin sees and edits everything
create policy "products read"   on public.products for select
  using (visible or public.is_admin());
create policy "products insert" on public.products for insert
  with check (public.is_admin());
create policy "products update" on public.products for update
  using (public.is_admin()) with check (public.is_admin());
create policy "products delete" on public.products for delete
  using (public.is_admin());

-- orders: users read their own, admin reads/updates all.
-- NOBODY inserts directly: orders are created only by place_order() below.
create policy "orders read own or admin" on public.orders for select
  using (user_id = auth.uid() or public.is_admin());
create policy "orders admin update" on public.orders for update
  using (public.is_admin()) with check (public.is_admin());

-- user_records: each user only touches their own rows
create policy "records own" on public.user_records for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- REALTIME (live product / order updates in the app) ----------
alter publication supabase_realtime add table public.products;
alter publication supabase_realtime add table public.orders;

-- ---------- FUNCTIONS ----------

-- Places an order in ONE transaction: checks stock, lowers it, saves the order.
-- Prices come from the products table (the app cannot fake them).
create or replace function public.place_order(
  p_order_id text,
  p_name     text,
  p_phone    text,
  p_address  text,
  p_payment  text,        -- 'cod' or 'xendit'
  p_items    jsonb        -- [{"productId": "...", "qty": 2}, ...]
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_pay   text := case when p_payment = 'xendit' then 'xendit' else 'cod' end;
  it      jsonb;
  prod    public.products%rowtype;
  v_qty   integer;
  v_items jsonb := '[]'::jsonb;
  v_total numeric := 0;
  v_count integer := 0;
begin
  if v_uid is null then raise exception 'Please log in first.'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.';
  end if;

  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := (it ->> 'qty')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Invalid quantity.'; end if;

    select * into prod from public.products where id = it ->> 'productId' for update;
    if not found or not prod.visible then
      raise exception 'An item in your cart is no longer available.';
    end if;
    if prod.stock < v_qty then
      raise exception '%', case when prod.stock <= 0
        then prod.name || ' just sold out.'
        else prod.name || ': only ' || prod.stock || ' left.' end;
    end if;

    update public.products set stock = stock - v_qty where id = prod.id;

    v_items := v_items || jsonb_build_object(
      'productId', prod.id, 'name', prod.name, 'category', prod.category,
      'unitPrice', prod.price, 'qty', v_qty, 'lineTotal', prod.price * v_qty);
    v_total := v_total + prod.price * v_qty;
    v_count := v_count + v_qty;
  end loop;

  insert into public.orders (
    id, user_id, user_email, customer_name, phone, address, items, item_count,
    total_price, payment_method, payment_status, status, date
  ) values (
    p_order_id, v_uid, auth.jwt() ->> 'email', trim(p_name), trim(p_phone), trim(p_address),
    v_items, v_count, v_total, v_pay,
    case when v_pay = 'xendit' then 'unpaid' else 'pay_on_delivery' end,
    case when v_pay = 'xendit' then 'awaiting_payment' else 'placed' end,
    to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );

  return jsonb_build_object('id', p_order_id, 'total', v_total);
end $$;

-- Cancels an unfinished order and puts the items back into stock.
-- Allowed for the admin and for the server (Xendit webhook uses the service role).
create or replace function public.cancel_order(p_order_id text, p_payment_status text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  o  public.orders%rowtype;
  it jsonb;
begin
  if not (public.is_admin() or coalesce(auth.role(), '') = 'service_role') then
    raise exception 'Not allowed.';
  end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found or o.status not in ('placed', 'awaiting_payment') then return; end if;

  for it in select * from jsonb_array_elements(o.items) loop
    update public.products
       set stock = stock + (it ->> 'qty')::integer
     where id = it ->> 'productId';
  end loop;

  update public.orders
     set status = 'cancelled',
         payment_status = coalesce(p_payment_status, payment_status)
   where id = p_order_id;
end $$;

-- Admin: add/remove stock (never below 0)
create or replace function public.adjust_stock(p_id text, p_delta integer)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not allowed.'; end if;
  update public.products
     set stock = greatest(0, stock + p_delta), updated_at = now()
   where id = p_id;
end $$;
