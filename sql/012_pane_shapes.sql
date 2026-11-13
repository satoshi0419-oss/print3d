-- ============================================================
-- 012: 縦ハーフ・縦1/4（薄い壁）を置けるようにする
--  ・blocks.shape（形）に使える番号を増やす
--      0 = ふつうのブロック、1 = 下ハーフ
--      2 = 縦ハーフ（東西にのびる）、3 = 縦ハーフ（南北にのびる）
--      4 = 縦1/4（東西にのびる）、  5 = 縦1/4（南北にのびる）
--  ・apply_blocks / room_blocks は 011 のまま使える（形の番号をそのまま受け渡すだけなので作り直し不要）
-- 使い方: SQL Editor に全文を貼って Run
-- ============================================================
alter table public.blocks drop constraint if exists blocks_shape_check;
alter table public.blocks add constraint blocks_shape_check check (shape between 0 and 5);
