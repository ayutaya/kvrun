## kvrun — ローカルに秘密を平文配置しないためのユーティリティ

`.env` 内の `kv://vault-name/secret-name` または `kv://vault-name/secret-name#version_id` を Azure Key Vault から取得し、後続コマンドへ渡します。
一時ファイルを作成せず、`kvrun` 自体はターミナルへ実値を出力しません。

1Password CLI ライクな記法で、.envにAzure Key Vaultから値を差し込みたくて作りました。

### 動作対象

 WSL2(Ubuntu) と macOS です。`kvrun` 本体の実行には Bash 4.3 以上が必要です。

### インストール

既定では `sudo` を使わず、ユーザー領域の `~/.local/bin` へインストールします。

```bash
bash install.sh
```

インストール後は次の 2 コマンドを利用できます。

- `kvrun`
- `kvrun-azure`

別のディレクトリへ入れる場合:

```bash
bash install.sh --install-dir "$HOME/bin"
```

#### WSL2 (Ubuntu)

- 通常はシステムの Bash が 4.3 以上で、そのままインストールできます
- `~/.local/bin` が `PATH` に入っていない場合は `~/.bashrc` などへ追加してください

```bash
export PATH="$HOME/.local/bin:$PATH"
```

#### macOS

- macOS 標準の `/bin/bash` は 3.2 系のことが多く、そのままでは `kvrun` を実行できません
- 先に Bash 4.3 以上を導入してください

```bash
brew install bash
bash install.sh
```

`install.sh` は見つけた Bash 4.3+ の絶対パスを `kvrun` に埋め込むため、実行時に古い `/bin/bash` を誤って使いにくくなります。

### 依存
- Bash 4.3+
- Azure CLIが動作する環境
- `az login` でログイン済みであること
- 対象 Key Vault のシークレット読み取り権限（`Key Vault Secrets User` ロール等）があること

## Azure 側操作

`kvrun-azure` は、`kvrun` 利用時に必要な Azure 側の操作をサブコマンドで提供します。

利用できるサブコマンド:

- `kvrun-azure app add-client-secret`
- `kvrun-azure vault create`
- `kvrun-azure secret add`

### Key Vault とサービスプリンシパルの初期作成

`kvrun-azure vault create` は、指定した作成先リソースグループが属する subscription / location を使って、`kvrun` 利用に必要な Azure 側リソースをまとめて作成します。

作成されるもの:

- RBAC 有効な Azure Key Vault
- 専用の Entra ID アプリ
- 上記アプリのサービスプリンシパル
- Key Vault への `Key Vault Secrets User` ロール割り当て

実行例:

```bash
kvrun-azure vault create \
  --resource-group my-app-rg \
  --name my-app-dev-kv
```

必要に応じて対象 subscription を明示できます。

```bash
kvrun-azure vault create \
  --resource-group my-app-rg \
  --name my-app-dev-kv \
  --subscription 00000000-0000-0000-0000-000000000000
```

必要に応じて Entra ID アプリ名やシークレット年数も指定できます。

```bash
kvrun-azure vault create --resource-group my-app-rg --name my-app-dev-kv --display-name kvrun-my-app-dev --years 1
```

完了すると、作成したサービスプリンシパルの `App ID`、`Tenant ID`、`az login` コマンドを 1 行で表示します。表示されるクライアントシークレットはその出力でのみ確認してください。

### 既存 Entra ID アプリへのクライアントシークレット追加

`kvrun-azure app add-client-secret` は、既存の Entra ID アプリへ追加のクライアントシークレットを発行します。`vault create` 実行時に表示された `App ID` を指定して、他の開発者向けのログイン情報を必要なタイミングで追加発行する想定です。

```bash
kvrun-azure app add-client-secret \
  --app-id 00000000-0000-0000-0000-000000000000
```

表示名や有効年数を変える場合:

```bash
kvrun-azure app add-client-secret \
  --app-id 00000000-0000-0000-0000-000000000000 \
  --display-name teammate-login \
  --years 1
```

完了すると、対象 `App ID`、`Tenant ID`、追加された `Password(Secret)`、そのまま使える `az login` コマンドを表示します。

### 既存 Key Vault へのシークレット追加

`kvrun-azure secret add` は、既存の Key Vault に新しいシークレットを追加します。値は TTY 接続時に非表示で対話入力し、非 TTY 時は標準入力から読み取ります。
同名シークレットが既に存在する場合、TTY では上書き確認を行い、非対話実行では安全のため中止します。
追加後は、新しい参照先として `kv://<vault-name>/<secret-name>#<version-id>` 形式を出力します。

```bash
kvrun-azure secret add \
  --resource-group my-app-rg \
  --name my-app-dev-kv \
  --secret-name db-password
```

非対話で流し込む場合:

```bash
printf 'super-secret\n' | kvrun-azure secret add \
  --resource-group my-app-rg \
  --name my-app-dev-kv \
  --secret-name db-password
```

### 使い方

```bash
kvrun <.env ファイルパス> <コマンド> [引数...]
```

**オプション:**

| オプション | 説明 |
|-----------|------|
| `-h`, `--help` | ヘルプを表示 |
| `-v`, `--version` | バージョンを表示 |
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
kvrun .env php artisan serve

# バージョン確認
kvrun --version

# Node.js 開発サーバーを起動
kvrun .env npm run dev

# 現在の環境変数を引き継がずに起動（デバッグ時のみ明示許可）
KVRUN_ALLOW_UNSAFE_COMMANDS=1 kvrun --no-inherit .env env

# 開発用 Vault / Subscription のみ許可して起動（推奨）
KVRUN_ALLOWED_VAULT_PATTERNS='*-dev,*-sandbox' \
KVRUN_ALLOWED_SUBSCRIPTION_IDS='00000000-0000-0000-0000-000000000000' \
kvrun --no-inherit .env php artisan serve
```

### 仕組み

```text
kvrun .env php artisan serve
     ↓
.env を1行ずつ読み込み:
  kv:// の値 → az keyvault secret show で実値へ変換（メモリ上のみ保持）
  通常の値  → そのまま保持
     ↓
export KEY=実値 ... してから exec php artisan serve
  ↑ kvrun プロセスは置き換えられて終了。後続プロセスがその PID を引き継ぐ。
```

### アンインストール

```bash
rm -f "$HOME/.local/bin/kvrun"
```

### リリース運用

Git タグを手動で先に作成してから `VERSION` を更新すると、タグ先コミット内の `VERSION` が古いまま残ります。  
そのため、このリポジトリでは GitHub Actions の `release` workflow からリリースする運用を推奨します。

1. GitHub Actions の `release` workflow を開く
2. `version` に `0.2.1` または `v0.2.1` を入力して実行する
3. workflow が `VERSION` を更新し、必要ならコミットした上で `v0.2.1` タグを作成する

なお、手動で `v*` タグを push した場合も `verify-tag-version` workflow が動き、タグ名と `VERSION` の不一致を検出します。

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
