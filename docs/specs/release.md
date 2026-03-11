# リリース運用

最終更新: 2026-03-12

## 1. 目的

このドキュメントは、`kvrun` のリリース時に `VERSION` と Git タグの不整合を防ぎ、公開手順を統一するための運用ルールを定義します。

現行仕様そのものは [現行仕様](../specs/current-spec.md) を参照してください。ここでは、リリース時の手順と禁止事項のみを扱います。

## 2. 基本ルール

- 正式なリリースは GitHub Actions の `release` workflow から実行する
- 手動で先に `v*` タグを作成して push しない
- `VERSION` とタグ名は常に一致させる
- リリース対象はリポジトリの default branch 上の最新状態とする

## 3. 推奨手順

1. GitHub Actions の `release` workflow を開く
2. `version` に `0.2.1` または `v0.2.1` 形式で入力して実行する
3. workflow が入力値を正規化し、`VERSION` を更新する
4. `VERSION` に差分がある場合のみ `chore: release vX.Y.Z` コミットを default branch へ push する
5. `vX.Y.Z` の注釈付きタグを作成して push する

## 4. `release` workflow の挙動

`release` workflow は次を自動で行います。

- 入力されたバージョン文字列を検証し、`v` 接頭辞の有無を正規化する
- default branch を checkout する
- 同名タグがローカルとリモートに存在しないことを確認する
- `VERSION` を更新する
- 差分がある場合のみ `VERSION` 更新コミットを作成して push する
- `vX.Y.Z` の注釈付きタグを作成して push する

## 5. バージョン入力ルール

- 許可形式は `0.2.1` または `v0.2.1`
- `1.2` や `v1.2-beta` のような形式は受け付けない
- workflow 内では `v` なしの値を `VERSION` に書き込み、`v` 付きの値をタグ名として使う

## 6. 禁止事項

- `VERSION` を更新する前に手動でタグを切ること
- `release` workflow を使わずに慣例的にタグだけ push すること
- タグ名と `VERSION` が一致しない状態で公開すること

## 7. 手動タグ push 時の検証

手動で `v*` タグを push した場合でも、GitHub Actions の `verify-tag-version` workflow が起動します。

この workflow は次を確認します。

- push されたタグ名から `v` を外した値
- タグ対象コミットに含まれる `VERSION` の値

この 2 つが一致しない場合、workflow は失敗します。

## 8. 関連ファイル

- `.github/workflows/release.yml`
- `.github/workflows/verify-tag-version.yml`
- `VERSION`
