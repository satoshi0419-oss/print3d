-- ============================================================
-- 010: 同じ高さ（Y）には1色だけ置ける（フィラメントの交換を減らす）
--  ・部屋ごとの設定 one_color_per_level（初期値 true）
--  ・ブロックの書き込みは apply_blocks で「1回の取引（トランザクション）」にまとめる
--    → 段の色をまとめて塗り替えるときも、途中の状態でルール違反と判定されない
--  ・書き込みの最後に「同じ高さに別の色がないか」をデータベースが確かめる（トリガー）
--    → 2人が同時に、空いている段に別の色を置いても、後の人は断られる
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================

alter table public.rooms add column if not exists one_color_per_level boolean not null default true;

-- ------------------------------------------------------------
-- 1. まとめて書き込む関数（置く・塗る・消すを1回で）
--    p_put = [[x,y,z,色,置いた人], ...]  p_del = [[x,y,z], ...]
--    security invoker = 呼んだ人の権限で動く → ロック中・時間外は RLS がそのまま断る
--    消せた個数を返す（ロック中は 0 になる）
-- ------------------------------------------------------------
create or replace function public.apply_blocks(p_room uuid, p_put json, p_del json)
returns int language plpgsql security invoker set search_path = public as $$
declare n_del int := 0;
begin
  if p_del is not null and json_array_length(p_del) > 0 then
    with c as (
      select (e->>0)::smallint as x, (e->>1)::smallint as y, (e->>2)::smallint as z from json_array_elements(p_del) as e
    ), d as (
      delete from blocks b using c where b.room_id = p_room and b.x = c.x and b.y = c.y and b.z = c.z returning 1
    ) select count(*) into n_del from d;
  end if;
  if p_put is not null and json_array_length(p_put) > 0 then
    insert into blocks (room_id, x, y, z, color, author, updated_at)
    select p_room, (e->>0)::smallint, (e->>1)::smallint, (e->>2)::smallint, (e->>3)::smallint, left(e->>4, 20), now()
    from json_array_elements(p_put) as e
    on conflict (room_id, x, y, z) do update set color = excluded.color, author = excluded.author, updated_at = now();
  end if;
  return n_del;
end $$;
grant execute on function public.apply_blocks(uuid, json, json) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. 同じ高さに別の色がないかの確認（取引の最後にまとめて行う = deferred）
--    advisory lock（合図用の鍵）で「同じ部屋・同じ高さ」の確認を1人ずつ順番にする
-- ------------------------------------------------------------
create or replace function public.blocks_one_color_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from rooms where id = new.room_id and one_color_per_level) then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.room_id::text || ':' || new.z::text, 0));
  if exists (select 1 from blocks where room_id = new.room_id and z = new.z and color <> new.color) then
    raise exception 'one_color_per_level: z=%', new.z;
  end if;
  return null;
end $$;

drop trigger if exists blocks_one_color on public.blocks;
create constraint trigger blocks_one_color
  after insert or update of color on public.blocks
  deferrable initially deferred
  for each row execute function public.blocks_one_color_check();

-- ------------------------------------------------------------
-- 3. 生徒が部屋コードで入るときに、この設定も返す（返す列が変わるので作り直す）
-- ------------------------------------------------------------
drop function if exists public.room_by_code(text);
create function public.room_by_code(p_code text)
returns table (id uuid, name text, max_colors int, mm_per_block numeric, m_per_block numeric, locked boolean,
               show_warnings boolean, size int, open_days smallint[], open_from time, open_until time, in_hours boolean,
               one_color_per_level boolean)
language sql security definer stable set search_path = public as $$
  select id, name, max_colors, mm_per_block, m_per_block, locked, show_warnings, size, open_days, open_from, open_until,
         room_in_hours(id), one_color_per_level
  from rooms where code = upper(trim(p_code));
$$;
grant execute on function public.room_by_code(text) to anon, authenticated;
