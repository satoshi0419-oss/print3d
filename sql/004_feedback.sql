-- ============================================================
-- 004: 感想（フィードバック）
--  ・誰でも送れる（生徒・先生・ひとりで試す）
--  ・読めるのは管理者だけ。送った本人も、他の先生も読めない
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================
create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  room_id    uuid references public.rooms(id)   on delete set null,
  school_id  uuid references public.schools(id) on delete set null,
  role       text not null check (role in ('teacher','student','solo')),
  nick       text check (char_length(nick) <= 30),
  category   text not null check (category in ('不具合','使いにくい','要望','よかった')),
  message    text not null check (char_length(message) between 1 and 1000),
  device     text check (char_length(device) <= 300),   -- 例: iPad / Safari
  context    jsonb,                                       -- ブロック数・接続状態・画面サイズなど
  resolved   boolean not null default false               -- 対応済みにしたら true
);

alter table public.feedback enable row level security;

drop policy if exists "feedback insert"       on public.feedback;
drop policy if exists "feedback admin read"   on public.feedback;
drop policy if exists "feedback admin update" on public.feedback;
drop policy if exists "feedback admin delete" on public.feedback;

-- 送る: 誰でも。ただし最初から「対応済み」では送れない
create policy "feedback insert" on public.feedback for insert to anon, authenticated with check (resolved = false);
-- 読む・対応済みにする・消す: 管理者だけ
create policy "feedback admin read"   on public.feedback for select to authenticated using (i_am_admin());
create policy "feedback admin update" on public.feedback for update to authenticated using (i_am_admin()) with check (i_am_admin());
create policy "feedback admin delete" on public.feedback for delete to authenticated using (i_am_admin());

revoke all on table public.feedback from anon, authenticated;
grant insert on table public.feedback to anon, authenticated;
grant select, update, delete on table public.feedback to authenticated;
