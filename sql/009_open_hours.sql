-- ============================================================
-- 009: 部屋に入れる時間帯（曜日と時刻）
--  ・open_days  : 入れる曜日（0=日 1=月 … 6=土）。null なら毎日
--  ・open_from / open_until : 入れる時刻（日本時間）。どちらかが null なら時刻の制限なし
--  ・時間外は、生徒はブロックを置けない・消せない（RLS で判定）。先生は時間外でも操作できる
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================
alter table public.rooms add column if not exists open_days  smallint[];
alter table public.rooms add column if not exists open_from  time;
alter table public.rooms add column if not exists open_until time;

-- 今が入れる時間帯か（日本時間で判定）
create or replace function public.room_in_hours(p_room uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((
    select (r.open_days is null or extract(dow from (now() at time zone 'Asia/Tokyo'))::smallint = any(r.open_days))
       and (r.open_from is null or r.open_until is null
            or (now() at time zone 'Asia/Tokyo')::time between r.open_from and r.open_until)
    from rooms r where r.id = p_room), false);
$$;
grant execute on function public.room_in_hours(uuid) to anon, authenticated;

-- 001 の room_is_open に「時間内」を足す（ブロック・操作記録の書き込みの判定に使われている）
create or replace function public.room_is_open(p_room uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from rooms where id = p_room and locked = false) and room_in_hours(p_room);
$$;

-- 生徒が部屋コードで入るときに、時間帯と「今入れるか」も返す（返す列が変わるので作り直す）
drop function if exists public.room_by_code(text);
create function public.room_by_code(p_code text)
returns table (id uuid, name text, max_colors int, mm_per_block numeric, m_per_block numeric, locked boolean,
               show_warnings boolean, size int, open_days smallint[], open_from time, open_until time, in_hours boolean)
language sql security definer stable set search_path = public as $$
  select id, name, max_colors, mm_per_block, m_per_block, locked, show_warnings, size, open_days, open_from, open_until, room_in_hours(id)
  from rooms where code = upper(trim(p_code));
$$;
grant execute on function public.room_by_code(text) to anon, authenticated;
