-- ============================================================
-- 007: まとめて消す関数と、同期のしかたの変更
--  ・範囲で空にする／たくさん消すときに、1回の通信で済ませる
--  ・ブロックの変更は、アプリ同士の Broadcast（お知らせ）で配るようにしたので、
--    データベースからの変更通知（Realtime の postgres_changes）は使わない → 配信の対象から外す
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================

-- p_cells = [[x,y,z], [x,y,z], ...]。消せた個数を返す。
-- security invoker = 呼んだ人の権限で動く → RLS（ロック中は生徒は消せない）がそのまま効く
create or replace function public.delete_blocks(p_room uuid, p_cells json)
returns int language sql security invoker set search_path = public as $$
  with c as (
    select (e->>0)::smallint as x, (e->>1)::smallint as y, (e->>2)::smallint as z
    from json_array_elements(p_cells) as e
  ), d as (
    delete from blocks b using c
    where b.room_id = p_room and b.x = c.x and b.y = c.y and b.z = c.z
    returning 1
  )
  select count(*)::int from d;
$$;
grant execute on function public.delete_blocks(uuid, json) to anon, authenticated;

-- blocks をデータベースの変更通知の対象から外す（もう使わないので、サーバーの負荷を減らす）
do $$ begin
  alter publication supabase_realtime drop table public.blocks;
exception when undefined_object then null; end $$;
