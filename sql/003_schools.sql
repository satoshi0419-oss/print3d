-- ============================================================
-- 003: 学校と先生のまとまり
--  ・先生は1つの学校に所属する
--  ・同じ学校の先生どうしは、お互いの部屋を一覧・開く・設定変更・削除できる
--  ・管理者（is_admin）はすべての学校の部屋を見られる（サポート用）
-- 使い方: SQL Editor に全文を貼って Run（何度流しても大丈夫な書き方にしてある）
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル
-- ------------------------------------------------------------
create table if not exists public.schools (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.teachers (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  school_id    uuid references public.schools(id) on delete set null,
  display_name text not null check (char_length(display_name) between 1 and 30),
  is_admin     boolean not null default false,
  created_at   timestamptz not null default now()
);

-- 部屋にも学校をひも付ける（既存の部屋は空欄のまま＝作った先生だけが見える）
alter table public.rooms add column if not exists school_id uuid references public.schools(id) on delete set null;

-- 試験運用の学校（必要に応じて追加）
insert into public.schools(name) values
  ('ひぎり舞岡小学校'), ('永谷小学校'), ('南戸塚小学校'), ('横浜国立大学附属特別支援学校'), ('KUMO lab')
on conflict (name) do nothing;

-- ------------------------------------------------------------
-- 2. ヘルパー関数（security definer = RLSを素通りして判定だけ返す）
-- ------------------------------------------------------------
create or replace function public.my_school()
returns uuid language sql security definer stable set search_path = public as $$
  select school_id from teachers where user_id = auth.uid();
$$;

create or replace function public.i_am_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from teachers where user_id = auth.uid()), false);
$$;

-- この部屋を管理してよいか: 作った本人 / 同じ学校の先生 / 管理者
create or replace function public.can_manage_room(p_owner uuid, p_school uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select p_owner = auth.uid()
      or (p_school is not null and p_school = my_school())
      or i_am_admin();
$$;

-- 001 で作った room_is_mine を「管理してよい部屋か」に広げる
-- （ロック中でも置ける・全部消す、が同じ学校の先生にもできるようになる）
create or replace function public.room_is_mine(p_room uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from rooms r where r.id = p_room and can_manage_room(r.owner_id, r.school_id));
$$;

grant execute on function public.my_school()               to authenticated;
grant execute on function public.i_am_admin()              to authenticated;
grant execute on function public.can_manage_room(uuid,uuid) to authenticated;

-- ------------------------------------------------------------
-- 3. RLS
-- ------------------------------------------------------------
alter table public.schools  enable row level security;
alter table public.teachers enable row level security;

-- schools: ログインした先生は学校名を読める
drop policy if exists "schools read" on public.schools;
create policy "schools read" on public.schools for select to authenticated using (true);

-- teachers: 自分と同じ学校の先生（名前を表示するため）、管理者は全員を読める。書き込みは管理者がSQLで行う
drop policy if exists "teachers read" on public.teachers;
create policy "teachers read" on public.teachers for select to authenticated
  using (user_id = auth.uid() or (school_id is not null and school_id = my_school()) or i_am_admin());

-- rooms: 001 の「作った本人だけ」を「管理してよい人」に置き換える
drop policy if exists "rooms owner select" on public.rooms;
drop policy if exists "rooms owner update" on public.rooms;
drop policy if exists "rooms owner delete" on public.rooms;
drop policy if exists "rooms owner insert" on public.rooms;
create policy "rooms owner select" on public.rooms for select to authenticated using (can_manage_room(owner_id, school_id));
create policy "rooms owner update" on public.rooms for update to authenticated using (can_manage_room(owner_id, school_id)) with check (can_manage_room(owner_id, school_id));
create policy "rooms owner delete" on public.rooms for delete to authenticated using (can_manage_room(owner_id, school_id));
-- 作るときは「自分が持ち主」かつ「学校は空欄か自分の学校」
create policy "rooms owner insert" on public.rooms for insert to authenticated
  with check (owner_id = auth.uid() and (school_id is null or school_id = my_school() or i_am_admin()));

grant select on table public.schools  to authenticated;
grant select on table public.teachers to authenticated;

-- ------------------------------------------------------------
-- 4. 先生を登録する関数（SQL Editor から管理者が呼ぶ。アプリからは呼べない）
--    先に Supabase の Authentication → Users → Add user でアカウントを作ってから呼ぶ。
--    例: select admin_register_teacher('taro@example.jp', 'ひぎり舞岡小学校', '山田先生');
-- ------------------------------------------------------------
create or replace function public.admin_register_teacher(p_email text, p_school text, p_name text, p_admin boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_school uuid;
begin
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then raise exception 'ユーザーが見つかりません: %（先に Authentication → Users で作成してください）', p_email; end if;
  select id into v_school from schools where name = p_school;
  if v_school is null then raise exception '学校が見つかりません: %', p_school; end if;
  insert into teachers(user_id, school_id, display_name, is_admin) values (v_user, v_school, p_name, p_admin)
  on conflict (user_id) do update set school_id = excluded.school_id, display_name = excluded.display_name, is_admin = excluded.is_admin;
  return p_name || ' を ' || p_school || ' に登録しました';
end $$;
revoke all on function public.admin_register_teacher(text,text,text,boolean) from public, anon, authenticated;
