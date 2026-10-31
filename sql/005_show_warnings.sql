-- ============================================================
-- 005: 生徒にも「浮いているブロック」の警告を見せるかどうか（部屋ごとの設定）
--  ・先生が部屋の設定でオン/オフする。初期値はオフ
--  ・生徒が部屋コードで入るときに使う room_by_code もこの値を返すようにする
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================
alter table public.rooms add column if not exists show_warnings boolean not null default false;

-- 返す列が増えるので、いったん消して作り直す（create or replace では戻り値の形を変えられない）
drop function if exists public.room_by_code(text);
create function public.room_by_code(p_code text)
returns table (id uuid, name text, max_colors int, mm_per_block numeric, m_per_block numeric, locked boolean, show_warnings boolean)
language sql security definer stable set search_path = public as $$
  select id, name, max_colors, mm_per_block, m_per_block, locked, show_warnings
  from rooms where code = upper(trim(p_code));
$$;
grant execute on function public.room_by_code(text) to anon, authenticated;
