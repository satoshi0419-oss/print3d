-- ============================================================
-- 011: ハーフブロック（下半分だけのブロック）
--  ・blocks に shape（形）を追加: 0 = ふつうのブロック、1 = 下ハーフ
--  ・apply_blocks は [x,y,z,色,置いた人,形] を受け取る（形を省くと 0）
--  ・room_blocks は [x,y,z,色,置いた人,形] を返す
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================
alter table public.blocks add column if not exists shape smallint not null default 0;
alter table public.blocks drop constraint if exists blocks_shape_check;
alter table public.blocks add constraint blocks_shape_check check (shape in (0, 1));

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
    insert into blocks (room_id, x, y, z, color, author, shape, updated_at)
    select p_room, (e->>0)::smallint, (e->>1)::smallint, (e->>2)::smallint, (e->>3)::smallint, left(e->>4, 20),
           coalesce((e->>5)::smallint, 0), now()
    from json_array_elements(p_put) as e
    on conflict (room_id, x, y, z) do update set color = excluded.color, author = excluded.author, shape = excluded.shape, updated_at = now();
  end if;
  return n_del;
end $$;
grant execute on function public.apply_blocks(uuid, json, json) to anon, authenticated;

create or replace function public.room_blocks(p_room uuid)
returns json language sql stable set search_path = public as $$
  select coalesce(json_agg(json_build_array(x, y, z, color, author, shape)), '[]'::json)
  from blocks where room_id = p_room;
$$;
grant execute on function public.room_blocks(uuid) to anon, authenticated;
