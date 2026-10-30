-- ============================================================
-- 校舎ブロック工房  データベース定義 (Supabase / PostgreSQL)
-- 使い方: Supabase ダッシュボード → SQL Editor に全文を貼り付けて Run
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル
-- ------------------------------------------------------------

-- 部屋 = 1クラス(1作品)。先生が作る。
create table if not exists public.rooms (
  id            uuid primary key default gen_random_uuid(),  -- UUID: Universally Unique IDentifier(世界で重複しない識別子)
  code          text not null unique,                        -- 生徒が入力する6文字の部屋コード
  name          text not null,                               -- 部屋の名前(例: 6年1組 校舎)
  owner_id      uuid not null references auth.users(id) on delete cascade, -- 作った先生
  max_colors    int  not null default 3  check (max_colors between 1 and 8),
  mm_per_block  numeric not null default 5,
  m_per_block   numeric not null default 1,
  locked        boolean not null default false,              -- true の間、生徒は置けない
  created_at    timestamptz not null default now()
);

-- ブロック = 1行が1個。位置が主キー(同じ場所には1個しか置けない)。
create table if not exists public.blocks (
  room_id    uuid not null references public.rooms(id) on delete cascade,
  x          smallint not null check (x between 0 and 63),
  y          smallint not null check (y between 0 and 63),
  z          smallint not null check (z between 0 and 63),
  color      smallint not null check (color between 0 and 7),
  author     text check (char_length(author) <= 20),         -- 置いた人のニックネーム
  updated_at timestamptz not null default now(),
  primary key (room_id, x, y, z)
);

-- ------------------------------------------------------------
-- 2. ヘルパー関数 (security definer = RLSを素通りして判定だけ返す)
--    ポリシーの中で rooms を直接見ると、生徒(anon)には rooms が見えないので
--    代わりにこの関数で「開いている部屋か」「自分の部屋か」を判定する。
-- ------------------------------------------------------------
create or replace function public.room_is_open(p_room uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from rooms where id = p_room and locked = false);
$$;

create or replace function public.room_is_mine(p_room uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from rooms where id = p_room and owner_id = auth.uid());
$$;

-- 生徒が部屋コードで部屋を探す。必要な列だけ返す(オーナーIDなどは返さない)。
create or replace function public.room_by_code(p_code text)
returns table (id uuid, name text, max_colors int, mm_per_block numeric, m_per_block numeric, locked boolean)
language sql security definer stable set search_path = public as $$
  select id, name, max_colors, mm_per_block, m_per_block, locked
  from rooms where code = upper(trim(p_code));
$$;

grant execute on function public.room_is_open(uuid)  to anon, authenticated;
grant execute on function public.room_is_mine(uuid)  to anon, authenticated;
grant execute on function public.room_by_code(text)  to anon, authenticated;

-- ------------------------------------------------------------
-- 3. RLS (Row Level Security = 行ごとのアクセス制限)
-- ------------------------------------------------------------
alter table public.rooms  enable row level security;
alter table public.blocks enable row level security;

-- rooms: 先生(ログイン済み)は自分の部屋だけ 見る・作る・変える・消す
drop policy if exists "rooms owner select" on public.rooms;
drop policy if exists "rooms owner insert" on public.rooms;
drop policy if exists "rooms owner update" on public.rooms;
drop policy if exists "rooms owner delete" on public.rooms;
create policy "rooms owner select" on public.rooms for select to authenticated using (owner_id = auth.uid());
create policy "rooms owner insert" on public.rooms for insert to authenticated with check (owner_id = auth.uid());
create policy "rooms owner update" on public.rooms for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "rooms owner delete" on public.rooms for delete to authenticated using (owner_id = auth.uid());

-- blocks: 読むのは誰でも(部屋IDを知っている人だけが読める。IDはUUIDなので推測はほぼ不可能)
drop policy if exists "blocks read"   on public.blocks;
drop policy if exists "blocks insert" on public.blocks;
drop policy if exists "blocks update" on public.blocks;
drop policy if exists "blocks delete" on public.blocks;
create policy "blocks read" on public.blocks for select to anon, authenticated using (true);

-- blocks: 書くのは「部屋がロックされていない」か「自分(先生)の部屋」のとき
create policy "blocks insert" on public.blocks for insert to anon, authenticated
  with check (room_is_open(room_id) or room_is_mine(room_id));
create policy "blocks update" on public.blocks for update to anon, authenticated
  using (room_is_open(room_id) or room_is_mine(room_id))
  with check (room_is_open(room_id) or room_is_mine(room_id));
create policy "blocks delete" on public.blocks for delete to anon, authenticated
  using (room_is_open(room_id) or room_is_mine(room_id));

-- ------------------------------------------------------------
-- 4. Realtime (変更をその場で全員に配る)
-- ------------------------------------------------------------
-- replica identity full: 削除されたとき、どの行が消えたか(x,y,z)を通知に含める
alter table public.blocks replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.blocks;
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- 5. 便利関数: 部屋のブロックを全部消す(先生だけ)
-- ------------------------------------------------------------
create or replace function public.clear_room(p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not room_is_mine(p_room) then raise exception 'not your room'; end if;
  delete from blocks where room_id = p_room;
end $$;
grant execute on function public.clear_room(uuid) to authenticated;
