# 校舎ブロック工房（フェーズ2: 教室版）

ブロックを積んで校舎を作り、3Dプリント用の STL を書き出すアプリ。
クラス全員が同じ部屋に入って同時に作れる。

## ファイル

| ファイル | 役割 |
|---|---|
| `index.html` | アプリ本体（生徒の入口・先生画面・エディタがすべて入った1ファイル） |
| `config.js` | Supabase への接続設定（URL と anon キー） |
| `sql/001_schema.sql` | データベース定義（部屋・ブロック）。SQL Editor に貼って実行する |
| `sql/002_grants.sql` | テーブルへのアクセス権（GRANT） |
| `sql/003_schools.sql` | 学校・先生のまとまりと、先生登録用の関数 |

## 初回セットアップ（約15分）

### 1. Supabase プロジェクトを作る
1. https://supabase.com → New project（Organization は既存のものでOK、無料枠）
2. リージョンは Northeast Asia (Tokyo) を選ぶ
3. できあがるまで1〜2分待つ

### 2. テーブルを作る
1. 左メニュー **SQL Editor** → New query
2. `sql/001_schema.sql` の中身を全部貼り付けて **Run**
3. 「Success. No rows returned」と出ればOK
4. 左メニュー **Table Editor** に `rooms` と `blocks` が見えることを確認

### 3. 接続設定を書く
1. 左メニュー **Project Settings → API**
2. `Project URL` と `anon public` キーをコピー
3. `config.js` の `supabaseUrl` と `supabaseAnonKey` に貼る

> anon（anonymous＝匿名）キーはブラウザに置いてよい公開用のキー。
> 「誰が何をしてよいか」はキーではなく RLS（Row Level Security＝行ごとのアクセス制限）が守る。
> その RLS を書いているのが `001_schema.sql` の 3 節。

### 4. 先生のアカウントを発行する（管理者の作業）
先生が自分で登録する方式ではなく、管理者が発行する方式にしている。

**最初に1回だけ**
1. `sql/002_grants.sql` → `sql/003_schools.sql` の順に SQL Editor で実行
2. Authentication → Sign In / Providers →「Allow new users to sign up」を **オフ**（誰でも登録できる状態を止める）
3. 自分を管理者として登録（すべての学校の部屋が見られる）
   ```sql
   select admin_register_teacher('satoshi0419@gmail.com', 'KUMO lab', '管理者', true);
   ```

**先生1人ごとに**
1. Authentication → Users →「Add user」→「Create new user」
   - Email: 先生のメールアドレス
   - Password: 仮パスワード（先生にお伝えし、ログイン後「パスワード変更」で変えてもらう）
   - **Auto Confirm User にチェック**（確認メールなしで使える。学校のメールは外部からのメールを受け取れないことがある）
2. SQL Editor で学校と表示名をひも付ける
   ```sql
   select admin_register_teacher('先生のメール', 'ひぎり舞岡小学校', '山田先生');
   ```
   学校名は `schools` テーブルにある名前と一字一句同じにする。学校を増やすときは
   ```sql
   insert into schools(name) values ('〇〇小学校');
   ```

**できること**
- 同じ学校の先生どうしは、お互いの部屋を一覧・開く・設定変更・削除できる
- 管理者はすべての学校の部屋を見られる（サポート用）
- 生徒は今までどおりアカウント不要（部屋コード＋ニックネーム）

### 5. Vercel に公開する
1. このフォルダを GitHub にプッシュ（非公開リポジトリでOK）
2. Vercel（KUMO lab チーム）→ Add New → Project → そのリポジトリを Import
3. Framework は **Other**、Build Command なし、Output Directory は空のまま → Deploy
4. 出てきた URL が生徒に配るアドレス

`config.js` にはキーが入るので、リポジトリは **非公開** にしておくこと（anon キーは公開されても RLS で守られるが、念のため）。

## 授業での使い方

### 先生
1. `https://（公開URL）/#teacher` を開いてログイン
2. 「部屋をつくる」→ 6文字の部屋コードが出る（例: `KAMO42`）
3. 「開く」で部屋に入る。先生の設定欄で
   - 使える色（2〜4色がおすすめ）
   - 1ブロック＝何mm（印刷）／何m（実物）
   - ロック（全員の手を止める）
4. 「生徒用リンクをコピー」で `?room=KAMO42` 付きのリンクが取れる

### 生徒
1. 公開URL（または先生のリンク）を開く
2. 部屋コードとニックネームを入れて「部屋に入る」
3. 置く・消す・塗る。他の人の作業はリアルタイムで見える

### 印刷
- 先生の画面で「STLファイルを書き出す」
- 「中を詰めて書き出す」はオンのまま（サポート材が不要になる）
- スライサーは 0.4mm ノズル・積層 0.2mm がおすすめ

## 仕組み（ざっくり）

```
生徒のブラウザ ──置く/消す──▶ Supabase の blocks テーブル（1行＝1ブロック）
      ▲                               │
      └──── Realtime（変更通知）◀──────┘   ← 全員の画面に即反映
      ◀──── Presence（今いる人）/ Broadcast（カーソル・設定変更）
```

- **部屋 (rooms)**: 1クラス1作品。先生のアカウントに紐づく
- **ブロック (blocks)**: 部屋ID + 位置(x,y,z) が主キー。同じ場所に2個は置けない＝後勝ち
- **生徒はアカウント不要**: 部屋コード（6文字）とニックネームだけ。DB上は anon（匿名）ユーザー
- **ロック**: rooms.locked = true の間、RLS が anon の書き込みを拒否する（画面側のチェックは補助）

## 開発メモ

- Three.js r128（CDN）で表示。STL は自前でバイナリ生成（三角形50バイト×枚数）
- 「内側の面を作らない」判定を 表示 と STL で共用しているので、見えたままが印刷される
- 1部屋のブロックは数千個を想定。読み込みは1000行ずつページング
- ひとりで試すモード（config.js が空でも動く）はブラウザの localStorage に保存
