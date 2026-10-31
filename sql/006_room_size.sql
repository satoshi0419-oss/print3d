-- ============================================================
-- 006: 作業台の広さ（部屋ごとに 32 / 64 / 128 マス）と、まとめて読み込む関数
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================

-- 部屋の広さ（既存の部屋は 32 のまま）
alter table public.rooms add column if not exists size int not null default 32;
alter table public.rooms drop constraint if exists rooms_size_check;
alter table public.rooms add constraint rooms_size_check check (size in (32, 64, 128));

-- ブロックの位置の上限を 0〜127 に広げる（高さ z は 0〜63 のまま）
alter table public.blocks drop constraint if exists blocks_x_check;
alter table public.blocks drop constraint if exists blocks_y_check;
alter table public.blocks add constraint blocks_x_check check (x between 0 and 127);
alter table public.blocks add constraint blocks_y_check check (y between 0 and 127);

-- 生徒が部屋コードで入るときに、広さも返す（返す列が変わるので作り直す）
drop function if exists public.room_by_code(text);
create function public.room_by_code(p_code text)
returns table (id uuid, name text, max_colors int, mm_per_block numeric, m_per_block numeric, locked boolean, show_warnings boolean, size int)
language sql security definer stable set search_path = public as $$
  select id, name, max_colors, mm_per_block, m_per_block, locked, show_warnings, size
  from rooms where code = upper(trim(p_code));
$$;
grant execute on function public.room_by_code(text) to anon, authenticated;

-- 部屋のブロックを1回でまとめて返す（[x, y, z, 色, 置いた人] の配列）
-- 通常の読み込みは1回1000行までなので、数万個あると何十回も取りに行くことになる
create or replace function public.room_blocks(p_room uuid)
returns json language sql stable set search_path = public as $$
  select coalesce(json_agg(json_build_array(x, y, z, color, author)), '[]'::json)
  from blocks where room_id = p_room;
$$;
grant execute on function public.room_blocks(uuid) to anon, authenticated;
