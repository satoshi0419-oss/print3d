-- ============================================================
-- 002: テーブルへのアクセス権 (GRANT)
-- 001 を流したあと「permission denied for table ...」が出る場合に実行する。
--
-- GRANT = 「このテーブルに触ってよい」という入口の許可
-- RLS   = 「触ってよい行はどれか」という中身の制限 (001 で設定済み)
-- 両方そろって初めて読み書きできる。
-- ============================================================

grant usage on schema public to anon, authenticated;

-- 先生(authenticated)は rooms を読み書き、生徒(anon)は rooms に直接は触らない(関数経由のみ)
grant select, insert, update, delete on table public.rooms  to authenticated;

-- blocks は生徒も先生も読み書き(どの行かは RLS が判定)
grant select, insert, update, delete on table public.blocks to anon, authenticated;

-- 今後作るテーブルにも自動で同じ権限が付くようにしておく
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public grant usage, select on sequences to anon, authenticated;
