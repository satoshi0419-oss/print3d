// ============================================================
// 接続設定
// Supabase ダッシュボード → Project Settings → API からコピーして貼る
//   Project URL        → supabaseUrl
//   anon public key    → supabaseAnonKey  (anon = anonymous。ブラウザに置いてよい公開キー。
//                        データの守りは RLS(sql/001_schema.sql) が担当する)
// 空のままだと「ひとりで試す」モードだけ使える。
// ============================================================
window.KOUSHA_CONFIG = {
  supabaseUrl: "https://uwoembistzzpesngflgv.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3b2VtYmlzdHp6cGVzbmdmbGd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNzkyMDMsImV4cCI6MjEwODk1NTIwM30.2zp8D7H3JUhdwFfObvzvSmaBYJ5ws_c96A7CRbtqj4w"
};
