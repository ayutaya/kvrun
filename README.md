# kvrun

`.env` 内の `kv://vault-name/secret-name` または `kv://vault-name/secret-name#version_id` を Azure Key Vault から取得し、後続コマンドへ環境変数として渡す Bash 製 CLI です。
一時ファイルを作成せず、`kvrun` 自体はターミナルへ secret の実値を出力しません。

同梱の `kvrun-azure` は、`kvrun` 利用時に必要な Azure 側セットアップやシークレット追加を補助します。

## Overview

1Password CLI ライクな記法で、.envにAzure Key Vaultから値を差し込みたくて作りました。

### 何を解決するか

- `.env` に平文 secret を置きたくない
- 開発者ごとに secret を配りたくない
- Azure Key Vault の secret をローカル開発時だけ使いたい
- アプリ本体に Azure SDK や Key Vault Provider を追加したくない
- AI ツールやコード検索に見えやすい場所から credential を外したい

### 何を解決しないか

- 起動後のプロセスからの secret 漏えい
- アプリケーションやデバッグコードによる secret 出力
- 標準出力、標準エラー、ログ基盤への漏えい
- 過剰権限な開発環境そのもののリスク
- 組織全体の Azure / Entra 権限設計の不備

`kvrun` は安全な環境を作るツールではなく、避けられる露出を一つ減らすためのツールです。

## Requirements

インストール前に、次を満たしていることを確認してください。

- 対応 OS: WSL2 (Ubuntu), macOS
- Bash 4.3 以上
- [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/?view=azure-cli-latest) (`az`コマンド) が利用可能
- `kvrun` で `Key Vault` を参照する場合は az login 済み

macOS の `/bin/bash` は 3.2 系のことが多いため、そのままでは `kvrun` を実行できません。Homebrew などで Bash 4.3 以上を入れてください。

### Azure 権限

`kvrun` / `kvrun-azure` はローカルのセットアップだけでは動きません。Azure 側で必要な権限が不足していると、インストール後の動作確認以前に失敗します。
初回導入時に迷わないよう、インストール前に Azure 側の前提も確認してください。

#### 既に Key Vault がある場合

`kvrun` を使うには、対象 Key Vault の secret 読み取り権限が必要です。通常は Key Vault や、シークレットのスコープで `Key Vault Secrets User / キー コンテナー シークレット ユーザー` を付与します。

#### Key Vault をこれから作る場合

`kvrun-azure vault create` を使うと、`kvrun` 用の Azure リソースをまとめて作成できます。

作成されるもの:

- RBAC 有効な Azure Key Vault
- 専用の Microsoft Entra ID アプリ
- 上記アプリのサービスプリンシパル
- Key Vault への `Key Vault Secrets User` ロール割り当て

このとき、Azure RBAC と Microsoft Entra ID の両方で権限が必要です。

| コマンド                            | 主に呼ぶ Azure CLI                                                                                                     | 必要な権限の目安                                                                                                                                              |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kvrun`                             | `az keyvault secret show`                                                                                              | 対象 Key Vault の secret 読み取り権限                                                                                                                         |
| `kvrun-azure vault create`          | `az keyvault create`, `az role assignment create`, `az ad app create`, `az ad app credential reset`, `az ad sp create` | Key Vault 作成とロール割り当てができる Azure RBAC 権限、加えて Entra アプリ作成・サービスプリンシパル作成・クライアントシークレット発行ができる Entra ID 権限 |
| `kvrun-azure app add-client-secret` | `az ad app credential reset --append`                                                                                  | 対象 Entra ID アプリへクライアントシークレットを追加できる Entra ID 権限                                                                                      |
| `kvrun-azure secret add`            | `az keyvault secret show`, `az keyvault secret set`                                                                    | 対象 Key Vault の secret 書き込み権限。通常は `Key Vault Secrets Officer / キー コンテナー シークレット責任者` 相当                                           |

> [!IMPORTANT]
> ロールの付与は `kvrun-azure` では自動化しません。Azure Portal などで明示的に設定する運用を前提としています。

## Installation

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

`install.sh` は、見つけた Bash 4.3+ の絶対パスを `kvrun` と `kvrun-azure` に埋め込みます。これにより、実行時に古い `/bin/bash` を誤って使わないようにしています。

### PATH の確認

`~/.local/bin` が `PATH` に入っていない場合は、`~/.bashrc` などへ追加してください。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Quick Start

既存 Key Vault を使うか、新規作成するかで開始手順が変わります。

### 既存 Key Vault を使う場合

1. `az login` を実行する
2. 対象 Key Vault の secret 読み取り権限があることを確認する
3. `.env` に `kv://...` 形式で参照を書く
4. `kvrun` でアプリを起動する

```dotenv
DB_PASSWORD=kv://my-app-dev/db-password
APP_KEY=kv://my-app-dev/app-key#0123456789abcdef0123456789abcdef
LOG_LEVEL=debug
```

```bash
kvrun .env php artisan serve
```

> [!TIP]
> ほかのアプリケーションで使用するための `.env` ファイルを `kvrun` で使用すると、意図しない値も後続に環境変数として渡されます。  
> kvrun 専用の `.env.kv` 等を用意して、`kvrun .env.kv php artisan serve` とすることで、必要な値のみを受け渡すことができます。

### Key Vault を新規作成する場合

1. `az login` を実行する
2. `kvrun-azure vault create` で Key Vault と専用 Entra アプリを作成する
3. 必要なら運用者や開発者へ Azure Portal で追加ロールを付与する
4. `kvrun-azure secret add` で secret を登録する
5. `.env` に出力された `kv://...#<version>` を設定する
6. `kvrun` でアプリを起動する

```bash
kvrun-azure vault create \
  --resource-group my-app-rg \
  --name my-app-dev-kv
```

```bash
kvrun-azure secret add \
  --resource-group my-app-rg \
  --name my-app-dev-kv \
  --secret-name db-password
```

## Usage

### `kvrun`

```bash
kvrun [オプション] <.env ファイルパス> <コマンド> [引数...]
```

| オプション        | 説明                                                                |
| ----------------- | ------------------------------------------------------------------- |
| `-h`, `--help`    | ヘルプを表示                                                        |
| `-v`, `--version` | バージョンを表示                                                    |
| `--verbose`       | Key Vault 参照時の詳細ログを表示                                    |
| `--no-inherit`    | 現在の環境変数を極力引き継がず、`.env` と最低限の基本環境変数で起動 |
| `--`              | オプション解析を終了                                                |

実行例:

```bash
# PHP Artisan を Key Vault の環境変数つきで起動
kvrun .env php artisan serve

# Key 名、Vault 名、Secret 名、Version を含む詳細ログを表示
kvrun --verbose .env php artisan serve

# Node.js 開発サーバーを起動
kvrun .env npm run dev

# 現在の環境変数を極力引き継がずに起動
kvrun --no-inherit .env php artisan serve
```

### `.env` ルール

`kvrun` は一般的な dotenv ローダーと完全互換ではありません。README だけ見て使い始めても詰まりにくいよう、先に制約を確認してください。

- 非コメント行は `KEY=VALUE` 形式必須
- キーは `^[A-Za-z_][A-Za-z0-9_]*$`
- 同一キーの重複定義はエラー
- `KEY=${OTHER_KEY}` のような変数展開は現時点では未対応
- 値は左側空白のみ除去し、右側空白は保持
- 値全体がシングルクォートまたはダブルクォートで囲まれている場合のみ外す
- `kv://` 参照は `kv://vault-name/secret-name` または `kv://vault-name/secret-name#version_id` の厳密形式のみ許可

記述例:

```dotenv
# 最新バージョンを取得
DB_PASSWORD=kv://my-app-dev/db-password

# 特定バージョンを取得
APP_KEY=kv://my-app-dev/app-key#0123456789abcdef0123456789abcdef

# kv:// でない値はそのまま渡す
LOG_LEVEL=debug
```

## 仕組み

`kvrun` は、指定した `.env` を 1 行ずつ読み込み、`kv://...` 形式の値だけを Azure Key Vault から解決して、最後に後続コマンドへ環境変数として渡して起動します。

大まかな流れは次のとおりです。

1. `.env` を読み込む
2. `KEY=VALUE` 形式として解釈する
3. 値が `kv://vault-name/secret-name` または `kv://vault-name/secret-name#version_id` なら Azure Key Vault から取得する
4. `kv://` でない値はそのまま使う
5. 解決済みの環境変数を設定して、後続コマンドを `exec` で起動する

このため、`.env` の内容を別ファイルへ展開して保存することはありません。
一方で、起動後のプロセスが環境変数として secret を参照できる点は通常の環境変数注入と同じです。

### Security Controls

環境変数で、誤利用しやすい対象を制限できます。

| 環境変数                         | 説明                                                           |
| -------------------------------- | -------------------------------------------------------------- |
| `KVRUN_ALLOWED_VAULT_PATTERNS`   | 許可する Vault 名パターン。カンマ区切り。例: `*-dev,*-sandbox` |
| `KVRUN_ALLOWED_SUBSCRIPTION_IDS` | 許可する Azure Subscription ID。カンマ区切り                   |
| `KVRUN_ALLOW_UNSAFE_COMMANDS`    | `1` の場合のみ `env` / `printenv` の実行を許可                 |

実行例:

```bash
# 開発用 Vault / Subscription のみ許可して起動
KVRUN_ALLOWED_VAULT_PATTERNS='*-dev,*-sandbox' \
KVRUN_ALLOWED_SUBSCRIPTION_IDS='00000000-0000-0000-0000-000000000000' \
kvrun --no-inherit .env php artisan serve

# デバッグ時のみ env を明示許可
KVRUN_ALLOW_UNSAFE_COMMANDS=1 kvrun --no-inherit .env env
```

`kvrun` 自体は secret の実値を出力しませんが、後続コマンドの出力は制御しません。`env` や `printenv` のような値を表示するコマンドは、必要時のみ明示的に許可して使ってください。

## Security Controls（セキュリティ制御）

`kvrun` を使ううえで、最低限知っておくべき仕様は次のとおりです。

- `kvrun` 自体は secret の実値を標準出力や標準エラーへ表示しません
- Azure CLI による secret 取得失敗時も、secret の実値そのものは表示しません
- `.env` は制約付きで解釈し、重複キーや不正な形式はエラーとして扱います`
- `kv://` 参照は厳密形式のみ受け付けます
- `env` / `printenv` のような誤利用しやすいコマンドは、既定では実行を拒否します
- 一時ファイルを作らず、解決結果を別ファイルへ保存しません

ただし、次は `kvrun` の守備範囲外です。

- 起動後のプロセスが環境変数を読むこと
- アプリケーション自身が secret をログや例外に出力すること
- `env` / `printenv` 以外の方法で後続コマンドが環境変数を表示すること
- 開発環境に過剰な Azure / Entra 権限が付与されていること
- AI ツールやログ収集基盤へ、実行後の出力をそのまま渡すこと

`env` / `printenv` の制限は、直接的で分かりやすい誤利用を減らすための簡易ガードです。任意の後続コマンド実行そのものを安全化するものではありません。

## Azure Helper Commands

`kvrun-azure` は、`kvrun` 利用時に必要な Azure 側操作をサブコマンドで提供します。

- `kvrun-azure vault create`
- `kvrun-azure app add-client-secret`
- `kvrun-azure secret add`

### `vault create`

指定したリソースグループの subscription / location を使って、`kvrun` 利用に必要な Azure 側リソースをまとめて作成します。

```bash
kvrun-azure vault create \
  --resource-group my-app-rg \
  --name my-app-dev-kv
```

必要に応じて subscription を明示できます。

```bash
kvrun-azure vault create \
  --resource-group my-app-rg \
  --name my-app-dev-kv \
  --subscription 00000000-0000-0000-0000-000000000000
```

Entra ID アプリ名やシークレット年数を指定する場合:

```bash
kvrun-azure vault create \
  --resource-group my-app-rg \
  --name my-app-dev-kv \
  --display-name kvrun-my-app-dev \
  --years 1
```

完了すると、`App ID`、`Tenant ID`、`az login` コマンド、`Password(Secret)` を表示します。クライアントシークレットはその出力でのみ確認してください。

### `app add-client-secret`

既存の Entra ID アプリへ追加のクライアントシークレットを発行します。`vault create` 実行時に表示された `App ID` を指定して、他の開発者向けのログイン情報を必要なタイミングで追加発行する用途です。

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

### `secret add`

既存の Key Vault に新しいシークレットを追加します。値は TTY 接続時に非表示で対話入力し、非 TTY 時は標準入力から読み取ります。
同名シークレットが既に存在する場合、TTY では上書き確認を行い、非対話実行では安全のため中止します。
追加後は、新しい参照先として `kv://<vault-name>/<secret-name>#<version-id>` を出力します。

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

## Uninstall

既定のインストール先から削除する場合:

```bash
rm -f "$HOME/.local/bin/kvrun" "$HOME/.local/bin/kvrun-azure"
```

別のディレクトリにインストールした場合は、そのディレクトリから同名ファイルを削除してください。

## Specification

詳細仕様や補足ドキュメントを確認したい場合は、次を参照してください。

- [現行仕様](docs/specs/current-spec.md)
