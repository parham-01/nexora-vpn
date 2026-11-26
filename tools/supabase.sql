-- NEXORA-SQL-VERSION: beta22-fix
-- =====================================================================
--  NEXORA / Parham VPN  —  Supabase SQL کامل (نسخه 3)
--  Supabase › SQL Editor › New query › همه را بچسبان › Run
--  چند بار اجرا شود هم امن است (idempotent) و داده‌ها پاک نمی‌شوند.
--  اگر Supabase هشدار «destructive operation» داد، تأیید کن (فقط
--  policy/constraint قدیمی حذف و دوباره ساخته می‌شود).
--
--  این نسخه چه چیزهایی را درست می‌کند:
--   1) ستون اضافه‌ی جدول‌های قدیمی که NOT NULL است و بدون مقدار
--      پیش‌فرض (دلیل خطای 23502 «null value» هنگام نوشتن در configs)
--   2) نوع ستون‌ها (id عددی، created_at عددی، ... → نوع درست)
--   3) کلید اصلی (PK) روی id، حذف ردیف‌های تکراری/خالی
--   4) policy ها / قیدهای (CHECK) قدیمی که جلوی نوشتن را می‌گیرند
--   5) تابع report_event (ثبت کاربر) — نسخه‌ی تک‌مرحله‌ای و مقاوم
--   6) دسترسی‌ها (anon فقط کانفیگ فعال بخواند و report_event بزند)
--   7) بکاپ داخلی، پاک‌سازی رویدادها، ایندکس‌ها
--   8) تابع nexora_health() و گزارش سلامت در انتهای اجرا
--   9) جدول Firefox (firefox_accounts + report_firefox) با امنیت RLS و تست سلامت
-- =====================================================================


-- =====================================================================
-- 0) توابع کمکی (فقط برای تبدیل امن نوع ستون‌ها)
-- =====================================================================
create or replace function public.nexora_num(v text)
returns numeric
language plpgsql
immutable
as $$
begin
  if v is null or btrim(v) = '' then
    return null;
  end if;
  return v::numeric;
exception when others then
  return null;
end;
$$;

create or replace function public.nexora_ts(v text)
returns timestamptz
language plpgsql
stable
as $$
declare
  n numeric;
begin
  if v is null or btrim(v) = '' then
    return null;
  end if;
  if btrim(v) ~ '^-?[0-9]+(\.[0-9]+)?$' then
    n := btrim(v)::numeric;
    if n > 100000000000 then
      n := n / 1000.0;      -- میلی‌ثانیه → ثانیه
    end if;
    return to_timestamp(n);
  end if;
  return v::timestamptz;
exception when others then
  return null;
end;
$$;

create or replace function public.nexora_bool(v text)
returns boolean
language sql
immutable
as $$
  select case
    when lower(btrim(coalesce(v, ''))) in ('t', 'true', '1', 'yes', 'y', 'on') then true
    when lower(btrim(coalesce(v, ''))) in ('f', 'false', '0', 'no', 'n', 'off') then false
    else null
  end
$$;

-- ساختار درست همه‌ی ستون‌ها (جدول، ستون، نوع، مقدار پیش‌فرض)
-- پیشوند مقدار پیش‌فرض:  S: متن  |  N: عدد  |  B: بولین  |  X: عبارت SQL
create or replace function public.nexora_spec()
returns table(tbl text, col text, typ text, def text)
language sql
immutable
as $$
  select * from (values
    -- ---------------- configs ----------------
    ('configs', 'id',         'text',        'X:substr(md5(random()::text || clock_timestamp()::text), 1, 8)'),
    ('configs', 'name',       'text',        'S:'),
    ('configs', 'link',       'text',        'S:'),
    ('configs', 'protocol',   'text',        'S:'),
    ('configs', 'transport',  'text',        'S:'),
    ('configs', 'security',   'text',        'S:'),
    ('configs', 'country',    'text',        'S:'),
    ('configs', 'code',       'text',        'S:'),
    ('configs', 'quota_gb',   'numeric',     'N:0'),
    ('configs', 'expires',    'text',        'S:'),
    ('configs', 'enabled',    'boolean',     'B:true'),
    ('configs', 'source',     'text',        'S:manual'),
    ('configs', 'created_at', 'timestamptz', 'X:now()'),
    -- ---------------- users ----------------
    ('users', 'id',                  'text',        null::text),
    ('users', 'platform',            'text',        'S:unknown'),
    ('users', 'first_seen',          'timestamptz', 'X:now()'),
    ('users', 'last_seen',           'timestamptz', 'X:now()'),
    ('users', 'connections',         'integer',     'N:0'),
    ('users', 'up',                  'bigint',      'N:0'),
    ('users', 'down',                'bigint',      'N:0'),
    ('users', 'seconds',             'bigint',      'N:0'),
    ('users', 'connected',           'boolean',     'B:false'),
    ('users', 'last_protocol',       'text',        'S:'),
    ('users', 'last_country',        'text',        'S:'),
    ('users', 'config_id',           'text',        'S:'),
    ('users', 'open_session',        'text',        'S:'),
    ('users', 'last_closed_session', 'text',        'S:'),
    -- ---------------- events ----------------
    ('events', 't',         'timestamptz', 'X:now()'),
    ('events', 'type',      'text',        'S:'),
    ('events', 'device_id', 'text',        'S:'),
    ('events', 'protocol',  'text',        'S:'),
    ('events', 'transport', 'text',        'S:'),
    ('events', 'country',   'text',        'S:'),
    ('events', 'up',        'bigint',      'N:0'),
    ('events', 'down',      'bigint',      'N:0'),
    ('events', 'seconds',   'bigint',      'N:0'),
    -- ---------------- backups ----------------
    ('backups', 'created_at', 'timestamptz', 'X:now()'),
    ('backups', 'label',      'text',        'S:')
  ) as v(tbl, col, typ, def)
$$;


-- =====================================================================
-- 1) ساخت جدول‌ها (اگر وجود نداشته باشند)
-- =====================================================================
create table if not exists public.configs (
  id          text primary key default substr(md5(random()::text || clock_timestamp()::text), 1, 8),
  name        text not null default '',
  link        text not null default '',
  protocol    text not null default '',
  transport   text not null default '',
  security    text not null default '',
  country     text not null default '',
  code        text not null default '',
  quota_gb    numeric not null default 0,
  expires     text not null default '',
  enabled     boolean not null default true,
  source      text not null default 'manual',
  created_at  timestamptz not null default now()
);

create table if not exists public.users (
  id                   text primary key,
  platform             text not null default 'unknown',
  first_seen           timestamptz not null default now(),
  last_seen            timestamptz not null default now(),
  connections          integer not null default 0,
  up                   bigint not null default 0,
  down                 bigint not null default 0,
  seconds              bigint not null default 0,
  connected            boolean not null default false,
  last_protocol        text not null default '',
  last_country         text not null default '',
  config_id            text not null default '',
  open_session         text not null default '',
  last_closed_session  text not null default ''
);

create table if not exists public.events (
  id         bigserial primary key,
  t          timestamptz not null default now(),
  type       text not null default '',
  device_id  text not null default '',
  protocol   text not null default '',
  transport  text not null default '',
  country    text not null default '',
  up         bigint not null default 0,
  down       bigint not null default 0,
  seconds    bigint not null default 0
);

create table if not exists public.backups (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  label       text not null default '',
  data        jsonb not null default '{}'::jsonb
);

alter table public.backups add column if not exists data jsonb not null default '{}'::jsonb;

-- ---------- جدول اتصال‌ها (هر ردیف = یک نشست اتصال) ----------
create table if not exists public.connections (
  id          bigserial primary key,
  device_id   text        not null default '',
  session     text        not null default '',
  config_id   text        not null default '',
  protocol    text        not null default '',
  transport   text        not null default '',
  country     text        not null default '',
  started_at  timestamptz not null default now(),
  ended_at    timestamptz,
  up          bigint      not null default 0,
  down        bigint      not null default 0,
  seconds     bigint      not null default 0
);

-- ---------- جدول پیام‌ها (اعلان ادمین برای همه‌ی کاربران؛ فقط خواندنی برای اپ) ----------
create table if not exists public.messages (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  title       text        not null default '',
  body        text        not null default '',
  kind        text        not null default 'info',   -- info | warning | update
  pinned      boolean     not null default false,
  enabled     boolean     not null default true,
  expires_at  timestamptz
);

-- اگر این جدول‌ها از نسخه‌ی قدیمی مانده باشند، ستون‌های ناقص اضافه می‌شوند (داده‌ها پاک نمی‌شود)
alter table public.messages add column if not exists created_at timestamptz not null default now();
alter table public.messages add column if not exists title      text        not null default '';
alter table public.messages add column if not exists body       text        not null default '';
alter table public.messages add column if not exists kind       text        not null default 'info';
alter table public.messages add column if not exists pinned     boolean     not null default false;
alter table public.messages add column if not exists enabled    boolean     not null default true;
alter table public.messages add column if not exists expires_at timestamptz;

alter table public.connections add column if not exists device_id  text        not null default '';
alter table public.connections add column if not exists session    text        not null default '';
alter table public.connections add column if not exists config_id  text        not null default '';
alter table public.connections add column if not exists protocol   text        not null default '';
alter table public.connections add column if not exists transport  text        not null default '';
alter table public.connections add column if not exists country    text        not null default '';
alter table public.connections add column if not exists started_at timestamptz not null default now();
alter table public.connections add column if not exists ended_at   timestamptz;
alter table public.connections add column if not exists up         bigint      not null default 0;
alter table public.connections add column if not exists down       bigint      not null default 0;
alter table public.connections add column if not exists seconds    bigint      not null default 0;



-- =====================================================================
-- 2) پاک‌سازی چیزهای قدیمی که جلوی تبدیل/نوشتن را می‌گیرند
--    (policy های قدیمی و قیدهای CHECK؛ نسخه‌ی درستشان پایین‌تر ساخته می‌شود)
-- =====================================================================
do $$
declare
  p record;
  c record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('configs', 'users', 'events', 'backups')
  loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;

  for c in
    select conrelid::regclass::text as tbl, conname
    from pg_constraint
    where contype = 'c'
      and conrelid in (
        to_regclass('public.configs'), to_regclass('public.users'),
        to_regclass('public.events'),  to_regclass('public.backups')
      )
  loop
    execute format('alter table %s drop constraint if exists %I', c.tbl, c.conname);
  end loop;
end $$;


-- =====================================================================
-- 3) اضافه کردن ستون‌های ناقص + تبدیل نوع ستون‌های اشتباه
--    مثال: id عددی → text ، created_at عددی (میلی‌ثانیه) → timestamptz
-- =====================================================================
do $$
declare
  s record;
  cur text;
  want text;
  expr text;
begin
  for s in select * from public.nexora_spec() loop
    if not exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = s.tbl and c.column_name = s.col
    ) then
      execute format('alter table public.%I add column %I %s', s.tbl, s.col, s.typ);
      continue;
    end if;

    select c.data_type into cur
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = s.tbl and c.column_name = s.col;

    want := case s.typ when 'timestamptz' then 'timestamp with time zone' else s.typ end;

    if cur is distinct from want then
      begin
        execute format('alter table public.%I alter column %I drop identity if exists', s.tbl, s.col);
      exception when others then null;
      end;
      begin
        execute format('alter table public.%I alter column %I drop default', s.tbl, s.col);
      exception when others then null;
      end;
      begin
        execute format('alter table public.%I alter column %I drop not null', s.tbl, s.col);
      exception when others then null;
      end;

      expr := case s.typ
        when 'text'        then format('%I::text', s.col)
        when 'timestamptz' then format('public.nexora_ts(%I::text)', s.col)
        when 'boolean'     then format('public.nexora_bool(%I::text)', s.col)
        when 'numeric'     then format('public.nexora_num(%I::text)', s.col)
        when 'integer'     then format('coalesce(round(public.nexora_num(%I::text)), 0)::integer', s.col)
        when 'bigint'      then format('coalesce(round(public.nexora_num(%I::text)), 0)::bigint', s.col)
      end;

      begin
        execute format('alter table public.%I alter column %I type %s using %s', s.tbl, s.col, s.typ, expr);
      exception when others then
        raise warning 'NEXORA: تبدیل %.% از % به % انجام نشد: %', s.tbl, s.col, cur, s.typ, sqlerrm;
      end;
    end if;
  end loop;
end $$;


-- =====================================================================
-- 4) ستون id جدول‌های events و backups (شمارنده‌ی خودکار) + کلید اصلی
-- =====================================================================
do $$
declare
  tn text;
  dt text;
  dflt text;
  ident text;
  seq text;
begin
  foreach tn in array array['events', 'backups'] loop
    select c.data_type, c.column_default, c.is_identity
      into dt, dflt, ident
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = tn and c.column_name = 'id';

    continue when dt is null;

    if dflt is null and ident = 'NO' then
      if dt in ('bigint', 'integer', 'smallint') then
        seq := 'public.' || tn || '_id_seq';
        execute format('create sequence if not exists %s', seq);
        execute format('alter sequence %s owned by public.%I.id', seq, tn);
        execute format('alter table public.%I alter column id set default nextval(%L)', tn, seq);
        execute format('select setval(%L, coalesce((select max(id) from public.%I), 0) + 1, false)', seq, tn);
      elsif dt = 'text' then
        execute format('alter table public.%I alter column id set default gen_random_uuid()::text', tn);
      elsif dt = 'uuid' then
        execute format('alter table public.%I alter column id set default gen_random_uuid()', tn);
      end if;
    end if;

    if not exists (
      select 1 from pg_constraint
      where conrelid = to_regclass('public.' || tn) and contype = 'p'
    ) then
      begin
        execute format('alter table public.%I add primary key (id)', tn);
      exception when others then
        raise warning 'NEXORA: کلید اصلی % ساخته نشد: %', tn, sqlerrm;
      end;
    end if;
  end loop;
end $$;


-- =====================================================================
-- 5) کلید اصلی روی id برای configs و users
--    (لازم برای upsert و on_conflict=id). ردیف‌های بدون id یا تکراری اصلاح می‌شوند.
-- =====================================================================
do $$
declare
  tn text;
  pk_name name;
  pk_cols name[];
begin
  foreach tn in array array['configs', 'users'] loop
    pk_name := null;
    pk_cols := null;

    select c.conname, array_agg(a.attname order by k.ord)
      into pk_name, pk_cols
    from pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.conrelid = to_regclass('public.' || tn) and c.contype = 'p'
    group by c.conname;

    if pk_name is not null and pk_cols is distinct from array['id']::name[] then
      execute format('alter table public.%I drop constraint %I cascade', tn, pk_name);
      pk_name := null;
    end if;

    if pk_name is null then
      execute format(
        'update public.%I set id = substr(md5(random()::text || clock_timestamp()::text), 1, 16) where id is null or length(btrim(id)) = 0',
        tn);
      execute format(
        'delete from public.%I a using public.%I b where a.id = b.id and a.ctid > b.ctid',
        tn, tn);
      execute format('alter table public.%I add primary key (id)', tn);
    end if;
  end loop;
end $$;


-- =====================================================================
-- 6) ستون‌های اضافه‌ی جدول‌های قدیمی (کلید حل خطای 23502)
--    هر ستونی که جزو ساختار ما نیست دیگر NOT NULL نیست، تا درج ردیف
--    جدید هیچ‌وقت به‌خاطر ستون ناشناس رد نشود.
-- =====================================================================
do $$
declare
  r record;
begin
  for r in
    select c.table_name::text as tn, c.column_name::text as cn
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name in ('configs', 'users', 'events', 'backups')
      and c.is_nullable = 'NO'
      and c.is_identity = 'NO'
      and not exists (
        select 1 from public.nexora_spec() s
        where s.tbl = c.table_name and s.col = c.column_name
      )
      and not (c.table_name in ('events', 'backups') and c.column_name = 'id')
      and not (c.table_name = 'backups' and c.column_name = 'data')
  loop
    begin
      execute format('alter table public.%I alter column %I drop not null', r.tn, r.cn);
    exception when others then
      raise warning 'NEXORA: NOT NULL ستون %.% برداشته نشد: %', r.tn, r.cn, sqlerrm;
    end;
  end loop;
end $$;


-- =====================================================================
-- 7) مقدار پیش‌فرض + پر کردن null ها + NOT NULL برای ستون‌های خودمان
-- =====================================================================
do $$
declare
  s record;
  d text;
begin
  for s in select * from public.nexora_spec() loop
    d := case
      when s.def is null then null
      when left(s.def, 2) = 'S:' then quote_literal(substr(s.def, 3))
      else substr(s.def, 3)
    end;

    begin
      if d is not null then
        execute format('update public.%I set %I = %s where %I is null', s.tbl, s.col, d, s.col);
        execute format('alter table public.%I alter column %I set default %s', s.tbl, s.col, d);
      else
        execute format('alter table public.%I alter column %I drop default', s.tbl, s.col);
      end if;
      execute format('alter table public.%I alter column %I set not null', s.tbl, s.col);
    exception when others then
      raise warning 'NEXORA: تنظیم ستون %.% انجام نشد: %', s.tbl, s.col, sqlerrm;
    end;
  end loop;
end $$;


-- =====================================================================
-- 8) ایندکس‌ها
-- =====================================================================
create index if not exists configs_created_idx   on public.configs (created_at);
create index if not exists configs_enabled_idx   on public.configs (enabled);
create index if not exists users_last_seen_idx   on public.users (last_seen desc);
create index if not exists users_config_idx      on public.users (config_id);
create index if not exists users_connected_idx   on public.users (connected, last_seen desc);
create index if not exists events_t_idx          on public.events (t desc);
create index if not exists events_type_t_idx     on public.events (type, t desc);
create index if not exists events_device_idx     on public.events (device_id);


-- =====================================================================
-- 9) قیدهای سلامت داده (روی داده‌ی قدیمی چک نمی‌شوند؛ فقط ردیف‌های جدید)
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'users_nonneg') then
    alter table public.users add constraint users_nonneg
      check (connections >= 0 and up >= 0 and down >= 0 and seconds >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'configs_quota_nonneg') then
    alter table public.configs add constraint configs_quota_nonneg
      check (quota_gb >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'events_nonneg') then
    alter table public.events add constraint events_nonneg
      check (up >= 0 and down >= 0 and seconds >= 0) not valid;
  end if;
end $$;


-- =====================================================================
-- 10) امنیت: RLS + policy
--     کلید anon (داخل اپ کاربر) فقط کانفیگ‌های فعال را می‌خواند
--     و فقط از راه report_event می‌تواند رویداد بفرستد.
-- =====================================================================
alter table public.configs enable row level security;
alter table public.users   enable row level security;
alter table public.events  enable row level security;
alter table public.backups enable row level security;

drop policy if exists "read active configs" on public.configs;
create policy "read active configs" on public.configs
  for select to anon, authenticated
  using (enabled = true);


-- =====================================================================
-- 11) توابع
-- =====================================================================
-- حذف نسخه‌های قدیمی/با امضای دیگر (جلوی خطای «چند تابع هم‌نام» را می‌گیرد)
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('report_event', 'create_backup', 'cleanup_old_events', 'nexora_health')
  loop
    execute format('drop function if exists %s', f.sig);
  end loop;
end $$;

-- ---------- 11-a) ثبت کاربر و رویداد اتصال (از اپ کاربر صدا زده می‌شود) ----------
create or replace function public.report_event(
  p_device    text,
  p_platform  text   default 'unknown',
  p_type      text   default 'hello',
  p_session   text   default '',
  p_protocol  text   default '',
  p_transport text   default '',
  p_country   text   default '',
  p_config    text   default '',
  p_up        bigint default 0,
  p_down      bigint default 0,
  p_seconds   bigint default 0
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dev    text   := lower(btrim(coalesce(p_device, '')));
  v_plat   text   := left(coalesce(nullif(btrim(coalesce(p_platform, '')), ''), 'unknown'), 20);
  v_type   text   := lower(btrim(coalesce(p_type, 'hello')));
  v_sess   text   := left(coalesce(p_session, ''), 64);
  v_proto  text   := left(coalesce(p_protocol, ''), 20);
  v_trans  text   := left(coalesce(p_transport, ''), 20);
  v_ctry   text   := left(coalesce(p_country, ''), 60);
  v_cfg    text   := left(coalesce(p_config, ''), 64);
  v_up     bigint := least(greatest(coalesce(p_up, 0), 0), 1000000000000000);
  v_down   bigint := least(greatest(coalesce(p_down, 0), 0), 1000000000000000);
  v_secs   bigint := least(greatest(coalesce(p_seconds, 0), 0), 1000000000);
  v_open   text;
  v_closed text;
begin
  -- شناسه‌ی دستگاه باید ۱۶ تا ۶۴ حرف hex باشد
  if v_dev !~ '^[a-f0-9]{16,64}$' then
    return;
  end if;

  -- ساخت کاربر (اگر نبود) یا به‌روزرسانی آخرین بازدید؛ در یک دستور
  insert into public.users as x (id, platform, first_seen, last_seen)
  values (v_dev, v_plat, now(), now())
  on conflict (id) do update
     set last_seen = now(),
         platform  = case when excluded.platform = 'unknown' then x.platform else excluded.platform end
  returning x.open_session, x.last_closed_session
  into v_open, v_closed;

  if v_type = 'connect' then
    if not (v_sess <> '' and v_open = v_sess) then
      insert into public.events (type, device_id, protocol, transport, country)
      values ('connect', v_dev, v_proto, v_trans, v_ctry);
      update public.users
         set connections = connections + 1,
             open_session = v_sess
       where id = v_dev;
      insert into public.connections (device_id, session, config_id, protocol, transport, country)
      values (v_dev, v_sess, case when exists (select 1 from public.configs c where c.id::text = v_cfg) then v_cfg else '' end,
              v_proto, v_trans, v_ctry);
    end if;
    update public.users
       set connected = true,
           last_protocol = v_proto,
           last_country = v_ctry,
           config_id = case
             when v_cfg <> '' and exists (select 1 from public.configs c where c.id::text = v_cfg) then v_cfg
             else config_id
           end
     where id = v_dev;

  elsif v_type = 'disconnect' then
    update public.users set connected = false where id = v_dev;
    if not (v_sess <> '' and v_closed = v_sess) then
      update public.users
         set up = up + v_up,
             down = down + v_down,
             seconds = seconds + v_secs,
             last_closed_session = v_sess,
             open_session = ''
       where id = v_dev;
      insert into public.events (type, device_id, up, down, seconds)
      values ('disconnect', v_dev, v_up, v_down, v_secs);
      update public.connections
         set ended_at = now(), up = v_up, down = v_down, seconds = v_secs
       where id = (select max(id) from public.connections
                    where device_id = v_dev and ended_at is null
                      and (v_sess = '' or session = v_sess));
    end if;

  elsif v_type = 'ping' then
    update public.users set connected = true where id = v_dev;
  end if;
end;
$$;

-- ---------- 11-b) نسخه‌ی پشتیبان داخل دیتابیس (۱۰ نسخه‌ی آخر) ----------
create or replace function public.create_backup(p_label text default '')
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  insert into public.backups (label, data)
  values (
    left(coalesce(p_label, ''), 80),
    jsonb_build_object(
      'app', 'parham-vpn',
      'version', 1,
      'createdAt', now(),
      'configs', coalesce((select jsonb_agg(to_jsonb(c)) from public.configs c), '[]'::jsonb),
      'users',   coalesce((select jsonb_agg(to_jsonb(u)) from public.users u), '[]'::jsonb)
    )
  )
  returning id into v_id;

  delete from public.backups
   where id not in (select b.id from public.backups b order by b.id desc limit 10);

  return v_id;
end;
$$;

-- ---------- 11-c) پاک‌سازی رویدادهای قدیمی:  select public.cleanup_old_events(180); ----------
create or replace function public.cleanup_old_events(p_days int default 180)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  n bigint;
begin
  delete from public.events
   where t < now() - make_interval(days => greatest(coalesce(p_days, 180), 7));
  get diagnostics n = row_count;
  delete from public.connections
   where started_at < now() - make_interval(days => greatest(coalesce(p_days, 180), 7));
  delete from public.messages
   where expires_at is not null and expires_at < now() - interval '30 days';
  return n;
end;
$$;

-- ---------- 11-d) تابع گزارش سلامت ----------
create or replace function public.nexora_health()
returns table(check_name text, ok boolean, detail text)
language plpgsql
security definer
set search_path = public
as $$
declare
  dev constant text := 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1';
  tid constant text := 'nexora-selftest';
  dev2 constant text := 'f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2';
  c4  bigint;
  tn  text;
  n   bigint;
  s   text;
  c1  bigint;
  c2  bigint;
  c3  bigint;
begin
  -- 1) وجود جدول‌ها
  foreach tn in array array['configs', 'users', 'events', 'backups', 'connections', 'messages', 'firefox_accounts', 'app_settings', 'user_backups'] loop
    check_name := 'جدول ' || tn;
    ok := to_regclass('public.' || tn) is not null;
    detail := case when ok then 'وجود دارد' else 'ساخته نشده' end;
    return next;
  end loop;

  -- 2) نوع ستون‌ها
  select string_agg(x.tbl || '.' || x.col || ' (' || coalesce(x.actual, 'missing') || ')', ', ')
    into s
  from (
    select sp.tbl, sp.col, c.data_type::text as actual,
           case sp.typ when 'timestamptz' then 'timestamp with time zone' else sp.typ end as want
    from public.nexora_spec() sp
    left join information_schema.columns c
      on c.table_schema = 'public' and c.table_name = sp.tbl and c.column_name = sp.col
  ) x
  where x.actual is distinct from x.want;
  check_name := 'نوع ستون‌ها';
  ok := s is null;
  detail := coalesce(s, 'همه درست است');
  return next;

  -- 3) ستون ناشناس اجباری بدون پیش‌فرض (دلیل خطای 23502)
  select string_agg(c.table_name || '.' || c.column_name, ', ')
    into s
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name in ('configs', 'users', 'events', 'backups')
    and c.is_nullable = 'NO'
    and c.column_default is null
    and c.is_identity = 'NO'
    and not exists (
      select 1 from public.nexora_spec() sp
      where sp.tbl = c.table_name and sp.col = c.column_name
    );
  check_name := 'ستون اجباریِ بدون مقدار پیش‌فرض';
  ok := s is null;
  detail := coalesce(s, 'ندارد');
  return next;

  -- 4) RLS
  select string_agg(cl.relname, ', ')
    into s
  from pg_class cl
  join pg_namespace ns on ns.oid = cl.relnamespace
  where ns.nspname = 'public'
    and cl.relname in ('configs', 'users', 'events', 'backups')
    and not cl.relrowsecurity;
  check_name := 'RLS فعال';
  ok := s is null;
  detail := coalesce('غیرفعال: ' || s, 'روی هر چهار جدول فعال است');
  return next;

  -- 5) policy کانفیگ‌ها
  select count(*) into n
  from pg_policies
  where schemaname = 'public' and tablename = 'configs' and policyname = 'read active configs';
  check_name := 'policy خواندن کانفیگ فعال';
  ok := n = 1;
  detail := case when ok then 'هست' else 'نیست' end;
  return next;

  -- 6) دسترسی anon
  check_name := 'anon: خواندن configs و اجرای report_event';
  begin
    ok := has_table_privilege('anon', 'public.configs', 'select')
      and has_function_privilege('anon', 'public.report_event(text,text,text,text,text,text,text,text,bigint,bigint,bigint)', 'execute');
    detail := case when ok then 'دسترسی دارد' else 'دسترسی ندارد' end;
  exception when others then
    ok := false;
    detail := sqlerrm;
  end;
  return next;

  check_name := 'anon: نباید users را بخواند';
  begin
    ok := not has_table_privilege('anon', 'public.users', 'select');
    detail := case when ok then 'بسته است' else 'باز است (خطرناک)' end;
  exception when others then
    ok := false;
    detail := sqlerrm;
  end;
  return next;

  -- 6-b) خواندن عمومی کانفیگ‌ها و حذف فقط برای ادمین
  check_name := 'anon: get_public_configs (خواندن زنده‌ی کانفیگ)';
  begin
    ok := has_function_privilege('anon', 'public.get_public_configs()', 'execute');
    detail := case when ok then 'دسترسی دارد' else 'دسترسی ندارد' end;
  exception when others then
    ok := false;
    detail := sqlerrm;
  end;
  return next;

  check_name := 'anon: نباید بتواند کانفیگ حذف کند';
  begin
    ok := not has_function_privilege('anon', 'public.admin_delete_config(text)', 'execute')
      and not has_table_privilege('anon', 'public.configs', 'delete');
    detail := case when ok then 'بسته است' else 'باز است (خطرناک)' end;
  exception when others then
    ok := false;
    detail := sqlerrm;
  end;
  return next;

  -- 7) تریگرهای قدیمی روی جدول‌ها (فقط اطلاع)
  select string_agg(tg.tgname || ' @ ' || cl.relname, ', ')
    into s
  from pg_trigger tg
  join pg_class cl on cl.oid = tg.tgrelid
  join pg_namespace ns on ns.oid = cl.relnamespace
  where not tg.tgisinternal
    and ns.nspname = 'public'
    and cl.relname in ('configs', 'users', 'events', 'backups');
  check_name := 'تریگرهای سفارشی';
  ok := true;
  detail := coalesce(s, 'ندارد');
  return next;

  -- 8) تست واقعی ثبت کاربر
  begin
    delete from public.events where device_id = dev;
    delete from public.users where id = dev;
    perform public.report_event(dev, 'selftest', 'hello');
    perform public.report_event(dev, 'selftest', 'connect', 'ab12ab12ab12ab12', 'vless', 'ws', 'Test', '');
    perform public.report_event(dev, 'selftest', 'disconnect', 'ab12ab12ab12ab12', '', '', '', '', 100, 200, 30);
    select count(*) into n
    from public.users u
    where u.id = dev and u.connections = 1 and u.up = 100 and u.down = 200 and u.seconds = 30;
    check_name := 'ثبت کاربر (report_event)';
    ok := n = 1;
    detail := case when ok then 'کاربر تستی ثبت شد و آمار درست حساب شد' else 'کاربر ثبت نشد یا آمار اشتباه است' end;
  exception when others then
    check_name := 'ثبت کاربر (report_event)';
    ok := false;
    detail := sqlerrm;
  end;
  return next;
  begin
    delete from public.events where device_id = dev;
    delete from public.users where id = dev;
  exception when others then null;
  end;

  -- 9) تست واقعی نوشتن در configs (همان کاری که تست اپ ادمین می‌کند)
  begin
    delete from public.configs where id = tid;
    insert into public.configs (id, name, link, source) values (tid, 't', 'x://t', 'test');
    delete from public.configs where id = tid;
    check_name := 'نوشتن در configs';
    ok := true;
    detail := 'درست کار می‌کند';
  exception when others then
    check_name := 'نوشتن در configs';
    ok := false;
    detail := sqlerrm;
  end;
  return next;

  -- 10) تست واقعی ثبت اکانت Firefox (report_firefox → firefox_accounts)
  begin
    delete from public.firefox_accounts where device_id = dev2;
    perform public.report_firefox(dev2,
      '[{"id":"selftest","label":"t***@x.com","enabled":true,"active":true,"unlimited":false,"used":100,"limit":1000,"remaining":900}]'::jsonb);
    select count(*) into n
    from public.firefox_accounts f
    where f.device_id = dev2 and f.acc_id = 'selftest' and f.used_bytes = 100 and f.limit_bytes = 1000 and f.remaining_bytes = 900;
    check_name := 'ثبت اکانت Firefox (report_firefox)';
    ok := n = 1;
    detail := case when ok then 'اکانت تستی در firefox_accounts ثبت شد' else 'ثبت نشد یا مقدارها اشتباه است' end;
  exception when others then
    check_name := 'ثبت اکانت Firefox (report_firefox)';
    ok := false;
    detail := sqlerrm;
  end;
  return next;
  begin
    delete from public.firefox_accounts where device_id = dev2;
  exception when others then null;
  end;

  check_name := 'anon: نباید firefox_accounts را بخواند';
  begin
    ok := not has_table_privilege('anon', 'public.firefox_accounts', 'select');
    detail := case when ok then 'بسته است' else 'باز است (خطرناک)' end;
  exception when others then
    ok := false;
    detail := sqlerrm;
  end;
  return next;

  -- 11) تعداد ردیف‌ها
  select count(*) into c1 from public.configs;
  select count(*) into c2 from public.users;
  select count(*) into c3 from public.events;
  begin
    select count(*) into c4 from public.firefox_accounts;
  exception when others then
    c4 := -1;
  end;
  check_name := 'تعداد ردیف‌ها';
  ok := true;
  detail := 'configs=' || c1 || '  users=' || c2 || '  events=' || c3 || '  firefox=' || c4;
  return next;

  return;
end;
$$;


-- =====================================================================
-- 12) دسترسی‌ها (GRANT / REVOKE)
-- =====================================================================
grant usage on schema public to anon, authenticated, service_role;

-- جدول‌ها: anon فقط configs را (و آن هم با RLS فقط فعال‌ها) می‌خواند
revoke all on public.configs, public.users, public.events, public.backups from anon, authenticated;
grant select on public.configs to anon, authenticated;
grant all on public.configs, public.users, public.events, public.backups to service_role;
grant usage, select, update on all sequences in schema public to service_role;

-- report_event: از اپ کاربر (anon) قابل صدا زدن است
revoke all on function public.report_event(text, text, text, text, text, text, text, text, bigint, bigint, bigint) from public;
grant execute on function public.report_event(text, text, text, text, text, text, text, text, bigint, bigint, bigint) to anon, authenticated, service_role;

-- بکاپ / پاک‌سازی / سلامت: فقط service_role (اپ ادمین)
revoke all on function public.create_backup(text) from public, anon, authenticated;
grant execute on function public.create_backup(text) to service_role;

revoke all on function public.cleanup_old_events(int) from public, anon, authenticated;
grant execute on function public.cleanup_old_events(int) to service_role;

revoke all on function public.nexora_health() from public, anon, authenticated;
grant execute on function public.nexora_health() to service_role;

-- توابع کمکی از بیرون قابل صدا زدن نباشند
revoke all on function public.nexora_spec() from public, anon, authenticated;
revoke all on function public.nexora_num(text) from public, anon, authenticated;
revoke all on function public.nexora_ts(text) from public, anon, authenticated;
revoke all on function public.nexora_bool(text) from public, anon, authenticated;



-- =====================================================================
-- 12-b) امنیت کامل (RLS) برای همه‌ی جدول‌ها
--   قانون: کاربر عادی (anon / authenticated) فقط «خواندن» دارد؛
--          نوشتن (Insert / Update / Delete) فقط با کلید service_role (اپ ادمین)
--          یا از راه تابع امن report_event.
--   service_role از RLS رد می‌شود؛ policy های بالا فقط برای کاربر عادی است.
-- =====================================================================
alter table public.configs     enable row level security;
alter table public.users       enable row level security;
alter table public.events      enable row level security;
alter table public.backups     enable row level security;
alter table public.connections enable row level security;
alter table public.messages    enable row level security;

-- ---------- خواندن عمومی (فقط چیزهای فعال) ----------
drop policy if exists "read active configs" on public.configs;
create policy "read active configs" on public.configs
  for select to anon, authenticated
  using (enabled = true);

drop policy if exists "read active messages" on public.messages;
create policy "read active messages" on public.messages
  for select to anon, authenticated
  using (enabled = true and (expires_at is null or expires_at > now()));

-- ---------- نوشتن برای کاربر عادی همیشه ممنوع (RESTRICTIVE یعنی روی هر policy دیگری هم غالب است) ----------
do $$
declare
  t text;
begin
  foreach t in array array['configs', 'users', 'events', 'backups', 'connections', 'messages']
  loop
    execute format('drop policy if exists %I on public.%I', 'deny insert ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'deny update ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'deny delete ' || t, t);
    execute format('create policy %I on public.%I as restrictive for insert to anon, authenticated with check (false)', 'deny insert ' || t, t);
    execute format('create policy %I on public.%I as restrictive for update to anon, authenticated using (false) with check (false)', 'deny update ' || t, t);
    execute format('create policy %I on public.%I as restrictive for delete to anon, authenticated using (false)', 'deny delete ' || t, t);
  end loop;
end $$;

-- ---------- جدول‌های خصوصی: خواندن هم برای کاربر عادی ممنوع ----------
do $$
declare
  t text;
begin
  foreach t in array array['users', 'events', 'backups', 'connections']
  loop
    execute format('drop policy if exists %I on public.%I', 'deny select ' || t, t);
    execute format('create policy %I on public.%I as restrictive for select to anon, authenticated using (false)', 'deny select ' || t, t);
  end loop;
end $$;

-- ---------- سطح دسترسی جدول‌ها (لایه‌ی دوم امنیت) ----------
revoke all on public.connections, public.messages from anon, authenticated;
grant select on public.messages to anon, authenticated;
grant all on public.connections, public.messages to service_role;
grant usage, select, update on all sequences in schema public to service_role;

-- جدول‌ها و تابع‌هایی که در آینده ساخته می‌شوند هم به‌صورت پیش‌فرض برای کاربر عادی بسته باشند
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated, public;

-- ---------- ایندکس‌ها ----------
create index if not exists connections_device_idx  on public.connections (device_id, started_at desc);
create index if not exists connections_started_idx on public.connections (started_at desc);
create index if not exists connections_open_idx    on public.connections (device_id) where ended_at is null;
create index if not exists messages_active_idx     on public.messages (pinned desc, created_at desc) where enabled;

-- ---------- قیدهای سلامت داده (فقط روی ردیف‌های جدید) ----------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'messages_kind_ck') then
    alter table public.messages add constraint messages_kind_ck check (kind in ('info', 'warning', 'update')) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'messages_len_ck') then
    alter table public.messages add constraint messages_len_ck check (char_length(title) <= 120 and char_length(body) <= 2000) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'connections_nonneg_ck') then
    alter table public.connections add constraint connections_nonneg_ck check (up >= 0 and down >= 0 and seconds >= 0) not valid;
  end if;
end $$;

-- =====================================================================
-- 13) پاک کردن باقیمانده‌ی تست‌های قبلی
-- =====================================================================
delete from public.configs where id in ('selftest-0', 'nexora-selftest');
delete from public.events  where device_id in ('f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0', 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1');
delete from public.users   where id in ('f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0', 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1');

-- توابع تبدیل دیگر لازم نیستند (دفعه‌ی بعد دوباره ساخته می‌شوند)
drop function if exists public.nexora_num(text);
drop function if exists public.nexora_ts(text);
drop function if exists public.nexora_bool(text);

-- به PostgREST بگو ساختار جدید را بخواند
notify pgrst, 'reload schema';
notify pgrst, 'reload config';


-- =====================================================================
-- 13-b) آمار اکانت‌های Firefox (از اپ کاربر گزارش می‌شود؛ فقط ایمیل ماسک‌شده ذخیره می‌شود)
-- =====================================================================
create table if not exists public.firefox_accounts (
  device_id        text        not null,
  acc_id           text        not null,
  label            text        not null default '',
  enabled          boolean     not null default true,
  active           boolean     not null default false,
  unlimited        boolean     not null default false,
  used_bytes       bigint      not null default 0,
  limit_bytes      bigint      not null default 0,
  remaining_bytes  bigint      not null default 0,
  first_seen       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (device_id, acc_id)
);

-- اگر جدول از نسخه‌ی قدیمی مانده باشد، ستون‌های ناقص اضافه می‌شوند (داده‌ها پاک نمی‌شود)
alter table public.firefox_accounts add column if not exists label           text        not null default '';
alter table public.firefox_accounts add column if not exists enabled         boolean     not null default true;
alter table public.firefox_accounts add column if not exists active          boolean     not null default false;
alter table public.firefox_accounts add column if not exists unlimited       boolean     not null default false;
alter table public.firefox_accounts add column if not exists used_bytes      bigint      not null default 0;
alter table public.firefox_accounts add column if not exists limit_bytes     bigint      not null default 0;
alter table public.firefox_accounts add column if not exists remaining_bytes bigint      not null default 0;
alter table public.firefox_accounts add column if not exists first_seen      timestamptz not null default now();
alter table public.firefox_accounts add column if not exists updated_at      timestamptz not null default now();

alter table public.firefox_accounts enable row level security;
revoke all on public.firefox_accounts from anon, authenticated;
grant all on public.firefox_accounts to service_role;

create index if not exists firefox_accounts_updated_idx on public.firefox_accounts (updated_at desc);
create index if not exists firefox_accounts_device_idx  on public.firefox_accounts (device_id);

-- کاربر عادی (anon) هیچ دسترسی مستقیمی به این جدول ندارد؛ فقط از راه report_firefox می‌نویسد
do $$
declare
  op text;
begin
  foreach op in array array['select', 'insert', 'update', 'delete'] loop
    execute format('drop policy if exists %I on public.firefox_accounts', 'deny ' || op || ' firefox_accounts');
  end loop;
  create policy "deny select firefox_accounts" on public.firefox_accounts as restrictive for select to anon, authenticated using (false);
  create policy "deny insert firefox_accounts" on public.firefox_accounts as restrictive for insert to anon, authenticated with check (false);
  create policy "deny update firefox_accounts" on public.firefox_accounts as restrictive for update to anon, authenticated using (false) with check (false);
  create policy "deny delete firefox_accounts" on public.firefox_accounts as restrictive for delete to anon, authenticated using (false);
end $$;

drop function if exists public.report_firefox(text, jsonb);
create or replace function public.report_firefox(p_device text, p_accounts jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dev  text := lower(btrim(coalesce(p_device, '')));
  v_list jsonb := coalesce(p_accounts, '[]'::jsonb);
  a      jsonb;
  v_id   text;
begin
  if v_dev !~ '^[a-f0-9]{16,64}$' then return; end if;
  if jsonb_typeof(v_list) <> 'array' or jsonb_array_length(v_list) > 30 then return; end if;

  delete from public.firefox_accounts
   where device_id = v_dev
     and not exists (select 1 from jsonb_array_elements(v_list) x where left(coalesce(x ->> 'id', ''), 64) = acc_id);

  for a in select * from jsonb_array_elements(v_list) loop
    v_id := left(coalesce(a ->> 'id', ''), 64);
    continue when v_id = '';
    begin
    insert into public.firefox_accounts
      (device_id, acc_id, label, enabled, active, unlimited, used_bytes, limit_bytes, remaining_bytes, updated_at)
    values (
      v_dev, v_id,
      left(coalesce(a ->> 'label', ''), 80),
      coalesce((a ->> 'enabled')::boolean, true),
      coalesce((a ->> 'active')::boolean, false),
      coalesce((a ->> 'unlimited')::boolean, false),
      least(greatest(coalesce((a ->> 'used')::numeric, 0), 0), 1000000000000000)::bigint,
      least(greatest(coalesce((a ->> 'limit')::numeric, 0), 0), 1000000000000000)::bigint,
      least(greatest(coalesce((a ->> 'remaining')::numeric, 0), 0), 1000000000000000)::bigint,
      now()
    )
    on conflict (device_id, acc_id) do update set
      label = excluded.label,
      enabled = excluded.enabled,
      active = excluded.active,
      unlimited = excluded.unlimited,
      used_bytes = excluded.used_bytes,
      limit_bytes = excluded.limit_bytes,
      remaining_bytes = excluded.remaining_bytes,
      updated_at = now();
    exception when others then
      null; -- یک اکانت خراب کل گزارش را خراب نکند
    end;
  end loop;
end;
$$;

revoke all on function public.report_firefox(text, jsonb) from public;
grant execute on function public.report_firefox(text, jsonb) to anon, authenticated, service_role;

-- حذف فوری یک اکانت Firefox از آمار (وقتی کاربر آن را از لیست اپ پاک می‌کند)
create or replace function public.forget_firefox(p_device text, p_acc text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dev text := lower(btrim(coalesce(p_device, '')));
begin
  if v_dev !~ '^[a-f0-9]{16,64}$' then return; end if;
  delete from public.firefox_accounts where device_id = v_dev and acc_id = left(coalesce(p_acc, ''), 64);
end;
$$;

revoke all on function public.forget_firefox(text, text) from public;
grant execute on function public.forget_firefox(text, text) to anon, authenticated, service_role;

-- آمار دقیق برای اپ ادمین: روز تقویمی به وقت p_tz (پیش‌فرض تهران)، کاربران امروز، نمودار ساعتی و روزانه
create or replace function public.admin_overview(p_tz text default 'Asia/Tehran', p_days int default 14)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  tz       text := coalesce(nullif(btrim(p_tz), ''), 'Asia/Tehran');
  n        int  := greatest(1, least(coalesce(p_days, 14), 90));
  d0       timestamptz;
  v_total  bigint;
  v_new    bigint;
  v_active bigint;
  v_online bigint;
  v_conn   bigint;
  v_hours  jsonb;
  v_days   jsonb;
begin
  begin
    perform now() at time zone tz;
  exception when others then
    tz := 'UTC';
  end;
  d0 := date_trunc('day', now() at time zone tz) at time zone tz;

  select count(*) into v_total from public.users;
  select count(*) into v_new from public.users where first_seen >= d0;
  select count(*) into v_active from public.users where last_seen >= d0;
  select count(*) into v_online from public.users where connected and last_seen > now() - interval '150 seconds';
  select count(*) into v_conn from public.connections where started_at >= d0;

  select coalesce(jsonb_agg(jsonb_build_object('h', g.h, 'users', coalesce(x.u, 0), 'events', coalesce(x.c, 0)) order by g.h), '[]'::jsonb)
    into v_hours
    from generate_series(0, 23) as g(h)
    left join (
      select extract(hour from e.t at time zone tz)::int as hh, count(distinct e.device_id) as u, count(*) as c
        from public.events e
       where e.t >= d0
       group by 1
    ) x on x.hh = g.h;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day', to_char(g.d, 'MM-DD'),
           'active', coalesce(a.u, 0),
           'new', coalesce(nw.c, 0),
           'connects', coalesce(cn.c, 0),
           'up', coalesce(cn.up, 0),
           'down', coalesce(cn.dn, 0)
         ) order by g.d), '[]'::jsonb)
    into v_days
    from generate_series(((now() at time zone tz)::date - (n - 1))::timestamp, (now() at time zone tz)::date::timestamp, interval '1 day') as g(d)
    left join (
      select (e.t at time zone tz)::date as dd, count(distinct e.device_id) as u
        from public.events e
       where e.t >= d0 - make_interval(days => n)
       group by 1
    ) a on a.dd = g.d::date
    left join (
      select (u.first_seen at time zone tz)::date as dd, count(*) as c
        from public.users u
       where u.first_seen >= d0 - make_interval(days => n)
       group by 1
    ) nw on nw.dd = g.d::date
    left join (
      select (c.started_at at time zone tz)::date as dd, count(*) as c, sum(c.up) as up, sum(c.down) as dn
        from public.connections c
       where c.started_at >= d0 - make_interval(days => n)
       group by 1
    ) cn on cn.dd = g.d::date;

  return jsonb_build_object(
    'tz', tz,
    'total', v_total,
    'newToday', v_new,
    'activeToday', v_active,
    'online', v_online,
    'connectsToday', v_conn,
    'hours', v_hours,
    'days', v_days
  );
end;
$$;

revoke all on function public.admin_overview(text, int) from public, anon, authenticated;
grant execute on function public.admin_overview(text, int) to service_role;

-- پاک کردن باقیمانده‌ی تست قبلی
delete from public.firefox_accounts where device_id = 'f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2';

notify pgrst, 'reload schema';

-- =====================================================================
-- 13-c) تنظیمات برنامه (مثلاً توکن گیت‌هاب برای خواندن ریلیزها)
--       فقط service_role (اپ ادمین) می‌نویسد؛ اپ کاربر فقط از تابع
--       get_app_setting کلیدهای مجاز را می‌خواند.
-- =====================================================================
create table if not exists public.app_settings (
  key        text        primary key,
  value      text        not null default '',
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
grant all on public.app_settings to service_role;

drop function if exists public.get_app_setting(text);
create or replace function public.get_app_setting(p_key text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select value from public.app_settings
   where key = p_key and key in ('github_token')
   limit 1;
$$;

revoke all on function public.get_app_setting(text) from public;
grant execute on function public.get_app_setting(text) to anon, authenticated, service_role;

-- =====================================================================
-- 13-c) بکاپ ابری رمزنگاری‌شده (اکانت‌ها و تنظیمات؛ بعد از حذف اپ با کد بازیابی برمی‌گردد)
--       سرور فقط متن رمزشده را نگه می‌دارد؛ کلید فقط پیش کاربر است.
-- =====================================================================
create table if not exists public.user_backups (
  id          text        primary key,
  blob        text        not null default '',
  device_id   text        not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.user_backups add column if not exists blob       text        not null default '';
alter table public.user_backups add column if not exists device_id  text        not null default '';
alter table public.user_backups add column if not exists created_at timestamptz not null default now();
alter table public.user_backups add column if not exists updated_at timestamptz not null default now();

alter table public.user_backups enable row level security;
revoke all on public.user_backups from anon, authenticated;
grant all on public.user_backups to service_role;

create index if not exists user_backups_updated_idx on public.user_backups (updated_at desc);

do $$
declare
  op text;
begin
  foreach op in array array['select', 'insert', 'update', 'delete'] loop
    execute format('drop policy if exists %I on public.user_backups', 'deny ' || op || ' user_backups');
  end loop;
  create policy "deny select user_backups" on public.user_backups as restrictive for select to anon, authenticated using (false);
  create policy "deny insert user_backups" on public.user_backups as restrictive for insert to anon, authenticated with check (false);
  create policy "deny update user_backups" on public.user_backups as restrictive for update to anon, authenticated using (false) with check (false);
  create policy "deny delete user_backups" on public.user_backups as restrictive for delete to anon, authenticated using (false);
end $$;

drop function if exists public.save_user_backup(text, text, text);
create or replace function public.save_user_backup(p_id text, p_blob text, p_device text default '')
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  text := lower(btrim(coalesce(p_id, '')));
  v_dev text := lower(btrim(coalesce(p_device, '')));
begin
  if v_id !~ '^[a-f0-9]{64}$' then return false; end if;
  if p_blob is null or length(p_blob) < 16 or length(p_blob) > 2000000 then return false; end if;
  if v_dev !~ '^[a-f0-9]{16,64}$' then v_dev := ''; end if;
  insert into public.user_backups (id, blob, device_id, updated_at)
  values (v_id, p_blob, v_dev, now())
  on conflict (id) do update set blob = excluded.blob, device_id = excluded.device_id, updated_at = now();
  return true;
end;
$$;

revoke all on function public.save_user_backup(text, text, text) from public;
grant execute on function public.save_user_backup(text, text, text) to anon, authenticated, service_role;

drop function if exists public.load_user_backup(text);
create or replace function public.load_user_backup(p_id text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select blob from public.user_backups
   where id = lower(btrim(coalesce(p_id, ''))) and lower(btrim(coalesce(p_id, ''))) ~ '^[a-f0-9]{64}$'
   limit 1;
$$;

revoke all on function public.load_user_backup(text) from public;
grant execute on function public.load_user_backup(text) to anon, authenticated, service_role;

notify pgrst, 'reload schema';

-- =====================================================================
-- 13-d) کانفیگ‌ها: خواندن عمومی با کلید anon (همان کلیدی که در بیلدر می‌گذاری) + حذف فوری
--       اپ کاربر کانفیگ‌ها را فقط از همین تابع (زنده از دیتابیس) می‌خواند، نه از فایل/کش.
--       حذف از اپ ادمین با admin_delete_config انجام می‌شود و تعداد ردیف حذف‌شده را برمی‌گرداند.
-- =====================================================================
drop function if exists public.get_public_configs();
create or replace function public.get_public_configs()
returns table(id text, name text, quota_gb numeric, expires text, link text,
              protocol text, transport text, country text, code text, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select c.id::text, coalesce(c.name::text, ''), coalesce(c.quota_gb::numeric, 0), coalesce(c.expires::text, ''), c.link::text, coalesce(c.protocol::text, ''), coalesce(c.transport::text, ''), coalesce(c.country::text, ''), coalesce(c.code::text, ''), c.created_at::timestamptz
    from public.configs c
   where c.enabled = true
   order by c.created_at asc
   limit 500;
$$;

revoke all on function public.get_public_configs() from public;
grant execute on function public.get_public_configs() to anon, authenticated, service_role;

drop function if exists public.admin_delete_config(text);
create or replace function public.admin_delete_config(p_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := btrim(coalesce(p_id, ''));
  n    integer := 0;
begin
  if v_id = '' then return 0; end if;
  delete from public.configs where id = v_id;
  get diagnostics n = row_count;
  update public.users set config_id = '' where config_id = v_id;
  return n;
end;
$$;

revoke all on function public.admin_delete_config(text) from public, anon, authenticated;
grant execute on function public.admin_delete_config(text) to service_role;

-- service_role همیشه اجازه‌ی کامل روی configs دارد (حذف/ویرایش از اپ ادمین)
grant select, insert, update, delete on public.configs to service_role;

notify pgrst, 'reload schema';

-- =====================================================================
-- 14) گزارش سلامت — همه‌ی ردیف‌ها باید ok = true باشند
--     (ردیف «تریگرهای سفارشی» فقط اطلاع است)
-- =====================================================================
do $do$
begin
  execute $f$create or replace function public.nexora_sql_version() returns text language sql immutable as $b$select 'beta22-fix'::text$b$$f$;
  execute 'grant execute on function public.nexora_sql_version() to anon, authenticated, service_role';
end
$do$;
notify pgrst, 'reload schema';

select * from public.nexora_health();
