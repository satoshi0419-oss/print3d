-- ============================================================
-- 008: 操作の記録（だれが・いつ・何個 置いた／消した／塗った）
--  ・各端末が自分の操作の数を、5秒ごとにまとめて1行ずつ書き込む
--  ・読めるのは、その部屋を管理できる先生（同じ学校の先生・管理者）だけ
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================
create table if not exists public.edit_log (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms(id) on delete cascade,
  author     text check (char_length(author) <= 30),
  placed     int  not null default 0 check (placed  >= 0),
  erased     int  not null default 0 check (erased  >= 0),
  painted    int  not null default 0 check (painted >= 0),
  created_at timestamptz not null default now()
);
create index if not exists edit_log_room_time on public.edit_log (room_id, created_at);

alter table public.edit_log enable row level security;
drop policy if exists "edit_log insert" on public.edit_log;
drop policy if exists "edit_log read"   on public.edit_log;
-- 書く: ブロックを置けるときと同じ条件（ロック中の生徒は書けない）
create policy "edit_log insert" on public.edit_log for insert to anon, authenticated
  with check (room_is_open(room_id) or room_is_mine(room_id));
-- 読む: その部屋を管理できる先生だけ
create policy "edit_log read" on public.edit_log for select to authenticated
  using (room_is_mine(room_id));

revoke all on table public.edit_log from anon, authenticated;
grant insert on table public.edit_log to anon, authenticated;
grant select on table public.edit_log to authenticated;

-- 先生用: 人ごとの合計（p_since 以降。null なら全期間）
create or replace function public.room_edit_summary(p_room uuid, p_since timestamptz default null)
returns table (author text, placed bigint, erased bigint, painted bigint)
language sql stable security invoker set search_path = public as $$
  select coalesce(author, '（不明）'), sum(placed), sum(erased), sum(painted)
  from edit_log
  where room_id = p_room and (p_since is null or created_at >= p_since)
  group by 1;
$$;
grant execute on function public.room_edit_summary(uuid, timestamptz) to authenticated;
