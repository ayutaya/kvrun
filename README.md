## kvrun — ローカルに秘密を平文配置しないためのユーティリティ

`.env` 内の `kv://vault-name/secret-name` または `kv://vault-name/secret-name#version_id` を Azure Key Vault から取得し、後続コマンドへ渡します。
一時ファイルを作成せず、`kvrun` 自体はターミナルへ実値を出力しません。

1Password CLI ライクな記法で、.envにAzure Key Vaultから値を差し込みたくて作りました。

### 依存
- Bash 4.3+
- Azure CLIが動作する環境
- `az login` でログイン済みであること
- 対象 Key Vault のシークレット読み取り権限（`Key Vault Secrets User` ロール等）があること

### 使い方

```bash
bin/kvrun <.env ファイルパス> <コマンド> [引数...]
```

**オプション:**

| オプション | 説明 |
|-----------|------|
| `-h`, `--help` | ヘルプを表示 |
| `--no-inherit` | 現在の環境変数を引き継がず `.env` の内容のみを渡す |
| `--` | オプション解析を終了 |

**セキュリティ制約（環境変数）:**

| 環境変数 | 説明 |
|-----------|------|
| `KVRUN_ALLOWED_VAULT_PATTERNS` | 許可する Vault 名パターン（カンマ区切り、例: `*-dev,*-sandbox`） |
| `KVRUN_ALLOWED_SUBSCRIPTION_IDS` | 許可する Azure Subscription ID（カンマ区切り） |
| `KVRUN_ALLOW_UNSAFE_COMMANDS` | `1` の場合のみ `env` / `printenv` の実行を許可（既定は拒否） |

### .env の記述例

`kv://` で始まる値は Key Vault から取得し、それ以外の値はそのまま渡します。

```dotenv
# 最新バージョンを取得
DB_PASSWORD=kv://my-app-dev/db-password

# 特定バージョンを取得
APP_KEY=kv://my-app-dev/app-key#0123456789abcdef0123456789abcdef

# kv:// でない値はそのまま渡す
LOG_LEVEL=debug
```

### 実行例

```bash
# PHP Artisan を Key Vault の環境変数つきで起動
bin/kvrun .env php artisan serve

# Node.js 開発サーバーを起動
bin/kvrun .env npm run dev

# 現在の環境変数を引き継がずに起動（デバッグ時のみ明示許可）
KVRUN_ALLOW_UNSAFE_COMMANDS=1 bin/kvrun --no-inherit .env env

# 開発用 Vault / Subscription のみ許可して起動（推奨）
KVRUN_ALLOWED_VAULT_PATTERNS='*-dev,*-sandbox' \
KVRUN_ALLOWED_SUBSCRIPTION_IDS='00000000-0000-0000-0000-000000000000' \
bin/kvrun --no-inherit .env php artisan serve
```

### 仕組み

```
kvrun .env php artisan serve
     ↓
.env を1行ずつ読み込み:
  kv:// の値 → az keyvault secret show で実値へ変換（メモリ上のみ保持）
  通常の値  → そのまま保持
     ↓
export KEY=実値 ... してから exec php artisan serve
  ↑ kvrun プロセスは置き換えられて終了。後続プロセスがその PID を引き継ぐ。
```

## このツールの位置づけ

### 何を解決するツールか

`kvrun` は、主に次のような問題に対して有効です。

- `.env` に平文 secret を置きたくない
- 開発者ごとに secret を配りたくない
- Azure Key Vault の secret をローカル開発時だけ使いたい
- Laravel アプリ本体に Azure SDK や Key Vault Provider を入れたくない
- AI ツールやコード検索に見えやすい場所から credential を外したい

### 何を解決しないか

`kvrun` は、次の問題を解決しません。

- 起動後のプロセスからの secret 漏えい
- アプリケーションコードやデバッグコードによる secret 出力
- 標準出力・標準エラー・ログ収集基盤への漏えい
- 本番相当の外部参照データや readonly 接続のリスク
- SSO セッションやマウント済み credential の露出
- 過剰権限な開発環境そのもの
- AI に実行ログ全文を返す設計
- 組織全体のクラウド権限設計の不備

`kvrun` は、**安全な環境を作るツールではなく、避けられる露出を一つ減らすツール**です。

### セキュリティ仕様（kvrun）

- `.env` のキーは `^[A-Za-z_][A-Za-z0-9_]*$` のみ許可（不正キーを拒否）
- コメント/空行以外で `KEY=VALUE` 形式でない行はエラー終了（設定ミスの見逃し防止）
- 同一キーの重複定義を拒否（意図しない上書きを防止）
- `kv://` 参照は `kv://vault-name/secret-name` または `kv://vault-name/secret-name#version_id` の厳密形式のみ許可
- `az` 失敗時は詳細 stderr を表示せず、固定メッセージのみ返す（秘匿情報漏えい防止）
- `env` / `printenv` は既定で実行拒否（必要時のみ `KVRUN_ALLOW_UNSAFE_COMMANDS=1` で明示許可）
- `kvrun` 自体はシークレット値を出力しないが、後続コマンドの出力制御はしない
- `env` など値を表示するコマンドはデバッグ時のみ使用し、通常運用では避ける
- 許可する Vault / Subscription を環境変数で制限することを推奨（特に本番環境での誤使用防止）
