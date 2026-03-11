# kvrun 現行仕様

最終更新: 2026-03-12  
対象バージョン: `0.2.0`

## 1. 目的

`kvrun` は、`.env` 内の `kv://...` 参照を Azure Key Vault から解決し、後続コマンドへ環境変数として渡すための Bash 製 CLI です。  
平文 secret を `.env` や一時ファイルへ保存せず、ローカル開発時に限定して Azure Key Vault の値を扱うことを主目的とします。

同梱の `kvrun-azure` は、`kvrun` 利用時に必要な Azure 側セットアップやシークレット追加を補助する CLI です。

## 2. 提供物

- `kvrun`
- `kvrun-azure`
- `install.sh`

## 3. 動作環境

- 対応 OS: WSL2 (Ubuntu), macOS
- 実行シェル: Bash 4.3 以上
- Azure CLI (`az`) が利用可能であること
- `kvrun` で Key Vault を参照する場合は `az login` 済みであること
- 対象 Key Vault のシークレット読み取り権限があること

## 4. install.sh の仕様

`install.sh` は `sudo` を使わず、ユーザー領域へ `kvrun` と `kvrun-azure` をインストールします。

### 4.1 既定値

- インストール先: `~/.local/bin`
- 配布対象: `kvrun`, `kvrun-azure`
- 実行時 Bash: インストール時に見つかった Bash 4.3+ の絶対パスを埋め込む

### 4.2 オプション

- `--install-dir <dir>`: インストール先を変更
- `--bash-path <path>`: 利用する Bash を明示指定
- `--force`: 既存配布スクリプトを上書き
- `-h`, `--help`: ヘルプ表示

### 4.3 安全設計

- インストール先がディレクトリでない場合は失敗
- 書き込み不可ディレクトリにはインストールしない
- 既存ファイルが `kvrun` 配布物と判定できない場合は、`--force` なしで上書きしない
- `VERSION` ファイルからリリースバージョンを埋め込む

## 5. kvrun の仕様

## 5.1 基本動作

`kvrun` は `.env` を 1 行ずつ読み込み、`KEY=VALUE` 形式の行を解釈します。

- 空行と `#` 始まりのコメント行は無視
- `export KEY=VALUE` 形式も受け付ける
- `kv://` で始まる値は Azure Key Vault から実値を取得
- それ以外の値はそのまま後続プロセスへ渡す
- 最後は `exec` で後続コマンドへ置き換わる

## 5.2 起動構文

```bash
kvrun [オプション] <.env ファイルパス> <コマンド> [引数...]
```

### 5.3 オプション

- `-h`, `--help`: ヘルプ表示
- `-v`, `--version`: バージョン表示
- `--verbose`: Key Vault 参照時の詳細ログを表示
- `--no-inherit`: 現在プロセスの環境変数を極力引き継がず、`.env` 由来の値だけで起動
- `--`: オプション解析を終了

### 5.4 .env 解釈ルール

- 非コメント行は `KEY=VALUE` 形式必須
- キーは `^[A-Za-z_][A-Za-z0-9_]*$`
- 同一キーの重複定義はエラー
- 値は左側空白のみ除去し、右側空白は保持
- 全体がシングルクォートまたはダブルクォートで囲まれている場合のみ外す

### 5.5 Key Vault 参照ルール

許可される形式:

```text
kv://vault-name/secret-name
kv://vault-name/secret-name#version_id
```

制約:

- Vault 名: 英数字と `-`、3 文字以上 24 文字以下
- Secret 名: 英数字と `-`
- Version ID: 英数字のみ

解決時の Azure CLI 呼び出し:

```bash
az keyvault secret show --vault-name <vault> --name <secret> [--version <version>] --query value --output tsv --only-show-errors
```

### 5.6 ログ仕様

通常ログでは、環境変数名・Vault 名・Secret 名・値は表示しません。

- 通常時:
  `Azure Key Vault からシークレットを取得しています。詳細は --verbose で表示できます。`
- `--verbose` 時:
  `key`, `vault`, `secret`, `version` を含む詳細ログを表示
- Azure CLI 実行失敗時:
  通常時は汎用エラーのみ表示し、参照識別子は出さない
- いずれの場合も secret の実値は表示しない

### 5.7 セキュリティ制約用環境変数

- `KVRUN_ALLOWED_VAULT_PATTERNS`
  許可する Vault 名パターンをカンマ区切りで指定。未指定時は制限なし
- `KVRUN_ALLOWED_SUBSCRIPTION_IDS`
  許可する Azure Subscription ID をカンマ区切りで指定。未指定時は制限なし
- `KVRUN_ALLOW_UNSAFE_COMMANDS`
  `1` の場合のみ `env` / `printenv` を許可

### 5.8 危険コマンド制御

既定では以下のコマンド実行を拒否します。

- `env`
- `printenv`

上記は環境変数の一括出力により secret が漏えいしやすいためです。  
明示的に `KVRUN_ALLOW_UNSAFE_COMMANDS=1` を指定した場合のみ許可します。

### 5.9 エラー時の方針

- Azure CLI の `stderr` はそのまま表示しない
- エラーメッセージは日本語で固定文中心
- secret の実値はエラー時も表示しない

## 6. kvrun-azure の仕様

## 6.1 起動構文

```bash
kvrun-azure <コマンドグループ> <サブコマンド> [オプション]
```

### 6.2 提供コマンド

- `app add-client-secret`
- `vault create`
- `secret add`

## 6.3 `vault create`

用途:

- RBAC 有効な Key Vault を作成
- 専用 Entra ID アプリを作成
- 対応するサービスプリンシパルを作成
- Key Vault に `Key Vault Secrets User` ロールを付与

主要オプション:

- `-g`, `--resource-group <name>` 必須
- `-n`, `--name`, `--vault-name <name>` 必須
- `--subscription <id|name>`
- `--display-name <name>`
- `--years <n>`

仕様:

- `--subscription` 未指定時は現在の既定 subscription を利用
- location は指定 resource group から解決
- Key Vault 名が既に存在する場合は失敗
- ロール付与は最大 10 回、2 秒間隔で再試行
- 完了時に `App ID`, `Tenant ID`, `az login` コマンド, `Password(Secret)` を表示

## 6.4 `app add-client-secret`

用途:

- 既存 Entra ID アプリへクライアントシークレットを追加発行

主要オプション:

- `--app-id <id>` 必須
- `--tenant <id>`
- `--subscription <id|name>`
- `--display-name <name>` 既定 `kvrun-login`
- `--years <n>` 既定 `2`

仕様:

- 既存 credential を消さず `--append` で追加する
- 完了時に `App ID`, `Tenant ID`, `az login` コマンド, `Password(Secret)` を表示

## 6.5 `secret add`

用途:

- 既存 Key Vault へシークレットを追加

主要オプション:

- `-g`, `--resource-group <name>` 必須
- `-n`, `--name`, `--vault-name <name>` 必須
- `--secret-name <name>` 必須
- `--subscription <id|name>`

仕様:

- TTY 接続時は非表示入力でシークレット値を受け取る
- 非 TTY 時は標準入力から 1 行読み取る
- 空文字は拒否
- 同名 secret が既に存在する場合:
  - TTY あり: 上書き確認を実施
  - 非対話: 安全のため失敗
- 追加成功後に `kv://<vault>/<secret>#<version>` を表示

## 7. 非機能仕様

- すべてのユーザー向けエラーメッセージは日本語
- Bash スクリプトのみで構成される
- テストスクリプト `tests/run_test.sh` で主要挙動を検証する
- `kvrun` は secret の実値を標準出力・標準エラーへ出力しない方針

## 8. 解決対象と非対象

### 解決対象

- `.env` に平文 secret を置きたくない
- 開発者ごとの secret 配布を避けたい
- ローカル開発時だけ Azure Key Vault を参照したい
- アプリ本体へ Azure SDK を直接組み込みたくない

### 解決しないこと

- 起動後プロセスからの secret 漏えい
- アプリケーションやデバッグコードによる secret 出力
- ログ基盤や標準出力への漏えい
- 過剰権限な開発環境自体のリスク
