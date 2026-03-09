#!/usr/bin/env bash
# kvrun 動作テストスクリプト
#
# 使い方:
#   bash tests/run_test.sh
#
# 前提:
#   - リポジトリルートから実行すること
#   - テスト 12 を実行する場合は KEYVAULT_NAME を設定すること
#   - az login 済みで KEYVAULT_NAME の vault/secret への読み取り権限があること

# set -e は使わない。各テストで終了コードを個別に確認するため
set -uo pipefail

# ---------------------------------------------------------------------------
# パス設定
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN="${REPO_ROOT}/bin/kvrun"
INSTALL_SCRIPT="${REPO_ROOT}/install.sh"
ENV_FILE="${SCRIPT_DIR}/.env.test"
KEYVAULT_NAME="${KEYVAULT_NAME:-}"
KEYVAULT_DB_PASSWORD_SECRET_NAME="${KEYVAULT_DB_PASSWORD_SECRET_NAME:-db-password}"
KEYVAULT_TEST_SECRET_NAME="${KEYVAULT_TEST_SECRET_NAME:-test-secret}"
KEYVAULT_DB_PASSWORD_VERSION="${KEYVAULT_DB_PASSWORD_VERSION:-}"
SYSTEM_PATH="${PATH:-/usr/bin:/bin}"

# ---------------------------------------------------------------------------
# ユーティリティ
# ---------------------------------------------------------------------------
pass() { echo "  ✅ PASS: $*"; }
fail() { echo "  ❌ FAIL: $*" >&2; FAILED=$((FAILED + 1)); }
section() { echo; echo "=== $* ==="; }

FAILED=0

# ---------------------------------------------------------------------------
# .env.test 生成（KEYVAULT_NAME から動的に生成）
# ---------------------------------------------------------------------------
generate_env_test_file() {
    local vault_name=""
    local db_password_version_uri=""

    if [[ -n "$KEYVAULT_NAME" ]]; then
        vault_name="$KEYVAULT_NAME"
        echo "  INFO: KEYVAULT_NAME=${vault_name} を使用して .env.test を生成します"
    else
        vault_name="example-dev-vault"
        echo "  INFO: KEYVAULT_NAME が未設定のため、プレースホルダで .env.test を生成します"
    fi

    if [[ -n "$KEYVAULT_DB_PASSWORD_VERSION" ]]; then
        db_password_version_uri="kv://${vault_name}/${KEYVAULT_DB_PASSWORD_SECRET_NAME}#${KEYVAULT_DB_PASSWORD_VERSION}"
    else
        db_password_version_uri="kv://${vault_name}/${KEYVAULT_DB_PASSWORD_SECRET_NAME}"
    fi

    cat > "$ENV_FILE" <<EOF
DB_PASSWORD=kv://${vault_name}/${KEYVAULT_DB_PASSWORD_SECRET_NAME}
DB_PASSWORD_VERSION=${db_password_version_uri}
TEST_SECRET=kv://${vault_name}/${KEYVAULT_TEST_SECRET_NAME}
PLAIN_VAR=hello
EOF
}

generate_env_test_file

# ---------------------------------------------------------------------------
# テスト 1: ヘルプ表示（終了コード 0）
# ---------------------------------------------------------------------------
section "1. ヘルプ表示"
OUTPUT="$(bash "$BIN" --help 2>&1)" || true
if echo "$OUTPUT" | grep -q "使い方"; then
    pass "--help が正常に表示された"
else
    fail "--help の出力に '使い方' が含まれていない"
fi

# ---------------------------------------------------------------------------
# テスト 2: 引数不足エラー（終了コード 1）
# ---------------------------------------------------------------------------
section "2. 引数不足エラー"
OUTPUT="$(bash "$BIN" 2>&1)" || true
if echo "$OUTPUT" | grep -q "引数が不足"; then
    pass "引数なしで適切なエラーメッセージが表示された"
else
    fail "引数なしでエラーメッセージが表示されなかった（出力: ${OUTPUT})"
fi

# ---------------------------------------------------------------------------
# テスト 3: 存在しない .env ファイルのエラー（終了コード 1）
# ---------------------------------------------------------------------------
section "3. .env ファイルが存在しない場合のエラー"
OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" /nonexistent/.env env 2>&1)" || true
if echo "$OUTPUT" | grep -q "見つかりません"; then
    pass "存在しない .env で適切なエラーが表示された"
else
    fail "存在しない .env でエラーが表示されなかった（出力: ${OUTPUT})"
fi

# ---------------------------------------------------------------------------
# テスト 4: 不正な kv:// URI のエラー（終了コード 1）
# ---------------------------------------------------------------------------
section "4. 不正な kv:// URI のエラー"
TMPENV="$(mktemp)"
echo "BAD=kv://no-slash-here" > "$TMPENV"
OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "形式が不正"; then
    pass "不正な kv:// URI で適切なエラーが表示された"
else
    fail "不正な kv:// URI でエラーが表示されなかった（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 5: 通常値のパース（kv:// なし）
# ---------------------------------------------------------------------------
section "5. 通常値のパース（kv:// なし）"
TMPENV="$(mktemp)"
printf 'PLAIN_VAR=hello\n# コメント\n\nANOTHER=world\n' > "$TMPENV"
OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" --no-inherit "$TMPENV" env 2>/dev/null)" || true
if echo "$OUTPUT" | grep -q "PLAIN_VAR=hello" && echo "$OUTPUT" | grep -q "ANOTHER=world"; then
    pass "通常値が正しく後続プロセスへ渡された"
else
    fail "通常値のパースに失敗した（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 6: 不正な環境変数キーを拒否
# ---------------------------------------------------------------------------
section "6. 不正な環境変数キーを拒否"
TMPENV="$(mktemp)"
echo "BAD-KEY=value" > "$TMPENV"
OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "環境変数キー形式が不正"; then
    pass "不正な環境変数キーを拒否できた"
else
    fail "不正キーの拒否に失敗した（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 7: 重複キーを拒否
# ---------------------------------------------------------------------------
section "7. 重複キーを拒否"
TMPENV="$(mktemp)"
printf 'DUP=value1\nDUP=value2\n' > "$TMPENV"
OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "複数回定義"; then
    pass "重複キーを拒否できた"
else
    fail "重複キーの拒否に失敗した（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 8: 許可外 Vault 名を拒否（az 不要）
# ---------------------------------------------------------------------------
section "8. 許可外 Vault 名を拒否（az 不要）"
TMPENV="$(mktemp)"
echo "DB_PASSWORD=kv://prod-vault/db-password" > "$TMPENV"
OUTPUT="$(KVRUN_ALLOWED_VAULT_PATTERNS='*-dev,*-sandbox' KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "許可されていない Vault 名"; then
    pass "Vault 名パターン制約が有効"
else
    fail "Vault 名パターン制約が効いていない（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 9: az エラー出力を漏えいしない
# ---------------------------------------------------------------------------
section "9. az エラー出力を漏えいしない"
TMPENV="$(mktemp)"
FAKE_AZ_DIR="$(mktemp -d)"
printf 'DB_PASSWORD=kv://my-app-dev/db-password\n' > "$TMPENV"
cat > "${FAKE_AZ_DIR}/az" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "account" && "$2" == "show" ]]; then
  echo "00000000-0000-0000-0000-000000000000"
  exit 0
fi

if [[ "$1" == "keyvault" && "$2" == "secret" && "$3" == "show" ]]; then
  echo "SENSITIVE_TOKEN_SHOULD_NOT_BE_PRINTED" >&2
  exit 1
fi

echo "unexpected az args" >&2
exit 1
EOF
chmod +x "${FAKE_AZ_DIR}/az"
OUTPUT="$(PATH="${FAKE_AZ_DIR}:$PATH" KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "SENSITIVE_TOKEN_SHOULD_NOT_BE_PRINTED"; then
    fail "az の stderr が漏えいしている（出力: ${OUTPUT})"
elif echo "$OUTPUT" | grep -q "取得に失敗"; then
    pass "az の stderr を漏えいせず固定メッセージで失敗できた"
else
    fail "想定した失敗メッセージが表示されない（出力: ${OUTPUT})"
fi
rm -rf "$FAKE_AZ_DIR"
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 10: バージョン付き kv:// で --version が渡される
# ---------------------------------------------------------------------------
section "10. バージョン付き kv:// で --version が渡される"
TMPENV="$(mktemp)"
FAKE_AZ_DIR="$(mktemp -d)"
printf 'DB_PASSWORD=kv://my-app-dev/db-password#abc123\n' > "$TMPENV"
cat > "${FAKE_AZ_DIR}/az" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "account" && "$2" == "show" ]]; then
  echo "00000000-0000-0000-0000-000000000000"
  exit 0
fi

if [[ "$1" == "keyvault" && "$2" == "secret" && "$3" == "show" ]]; then
  version=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--version" ]]; then
      version="$2"
      break
    fi
    shift
  done

  if [[ "$version" == "abc123" ]]; then
    echo "resolved-from-version"
    exit 0
  fi

  echo "version option missing" >&2
  exit 1
fi

echo "unexpected az args" >&2
exit 1
EOF
chmod +x "${FAKE_AZ_DIR}/az"
OUTPUT="$(PATH="${FAKE_AZ_DIR}:$PATH" KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" --no-inherit "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "^DB_PASSWORD=resolved-from-version"; then
    pass "--version 付きでシークレット取得できた"
else
    fail "--version 付き取得に失敗した（出力: ${OUTPUT})"
fi
rm -rf "$FAKE_AZ_DIR"
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 11: 不正なバージョン ID を拒否
# ---------------------------------------------------------------------------
section "11. 不正なバージョン ID を拒否"
TMPENV="$(mktemp)"
echo "DB_PASSWORD=kv://my-app-dev/db-password#bad-version" > "$TMPENV"
OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "バージョン ID の形式が不正"; then
    pass "不正なバージョン ID を拒否できた"
else
    fail "不正なバージョン ID の拒否に失敗した（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 12: Azure Key Vault から実値を取得（az login 必須）
# ---------------------------------------------------------------------------
section "12. Azure Key Vault からの実値取得（az login 必須）"
if ! command -v az &>/dev/null; then
    echo "  ⚠️  SKIP: az コマンドが見つかりません"
elif [[ -z "$KEYVAULT_NAME" ]]; then
    echo "  ⚠️  SKIP: KEYVAULT_NAME が未設定です（例: export KEYVAULT_NAME=my-app-dev-vault）"
elif ! az account show &>/dev/null 2>&1; then
    echo "  ⚠️  SKIP: az login が完了していません"
else
    echo "  .env.test: ${ENV_FILE}"
    OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" --no-inherit "$ENV_FILE" env 2>/dev/null)" || true

    # テストのために出力全体を表示（実際の値は伏せるべきだが、テスト環境なので許容）
    echo "  OUTPUT:"
    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "^DB_PASSWORD="; then
        RESOLVED_VAL="$(echo "$OUTPUT" | grep '^DB_PASSWORD=' | cut -d= -f2-)"
        if [[ "$RESOLVED_VAL" != "kv://"* && -n "$RESOLVED_VAL" ]]; then
            pass "DB_PASSWORD が Key Vault から実値へ解決された"
        else
            fail "DB_PASSWORD が kv:// のまま（解決されていない）: ${RESOLVED_VAL}"
        fi
    else
        fail "DB_PASSWORD が出力に含まれていない（Key Vault 取得エラーの可能性）"
    fi

    if echo "$OUTPUT" | grep -q "^DB_PASSWORD_VERSION="; then
        RESOLVED_VAL="$(echo "$OUTPUT" | grep '^DB_PASSWORD_VERSION=' | cut -d= -f2-)"
        if [[ "$RESOLVED_VAL" != "kv://"* && -n "$RESOLVED_VAL" ]]; then
            pass "DB_PASSWORD_VERSION が Key Vault から実値へ解決された"
        else
            fail "DB_PASSWORD_VERSION が kv:// のまま（解決されていない）: ${RESOLVED_VAL}"
        fi
    else
        fail "DB_PASSWORD_VERSION が出力に含まれていない（Key Vault 取得エラーの可能性：vault名や参照権限の設定を確認してください）"
    fi

    if echo "$OUTPUT" | grep -q "^TEST_SECRET="; then
        RESOLVED_VAL="$(echo "$OUTPUT" | grep '^TEST_SECRET=' | cut -d= -f2-)"
        if [[ "$RESOLVED_VAL" != "kv://"* && -n "$RESOLVED_VAL" ]]; then
            pass "TEST_SECRET が Key Vault から実値へ解決された"
        else
            fail "TEST_SECRET が kv:// のまま（解決されていない）: ${RESOLVED_VAL}"
        fi
    else
        fail "TEST_SECRET が出力に含まれていない（Key Vault 取得エラーの可能性：vault名や参照権限の設定を確認してください）"
    fi

    if echo "$OUTPUT" | grep -q "^PLAIN_VAR=hello"; then
        pass "PLAIN_VAR=hello がそのまま渡された"
    else
        fail "PLAIN_VAR が正しく渡されていない"
    fi
fi

# ---------------------------------------------------------------------------
# テスト 13: KEY=VALUE 形式でない行を拒否
# ---------------------------------------------------------------------------
section "13. KEY=VALUE 形式でない行を拒否"
TMPENV="$(mktemp)"
printf 'GOOD=value\nBROKEN_LINE\n' > "$TMPENV"
OUTPUT="$(bash "$BIN" "$TMPENV" true 2>&1)" || true
if echo "$OUTPUT" | grep -q "KEY=VALUE 形式"; then
    pass "不正行を見逃さずエラー終了できた"
else
    fail "不正行を検出できなかった（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 14: 危険コマンド env を既定で拒否
# ---------------------------------------------------------------------------
section "14. 危険コマンド env を既定で拒否"
TMPENV="$(mktemp)"
printf 'SAFE_VAR=ok\n' > "$TMPENV"
OUTPUT="$(bash "$BIN" --no-inherit "$TMPENV" env 2>&1)" || true
if echo "$OUTPUT" | grep -q "実行を拒否"; then
    pass "env を既定で拒否できた"
else
    fail "env の既定拒否に失敗した（出力: ${OUTPUT})"
fi

OUTPUT="$(KVRUN_ALLOW_UNSAFE_COMMANDS=1 bash "$BIN" --no-inherit "$TMPENV" env 2>/dev/null)" || true
if echo "$OUTPUT" | grep -q "^SAFE_VAR=ok"; then
    pass "明示許可時のみ env 実行できた"
else
    fail "明示許可時の env 実行に失敗した（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 15: 非クォート値の末尾空白を保持
# ---------------------------------------------------------------------------
section "15. 非クォート値の末尾空白を保持"
TMPENV="$(mktemp)"
printf 'TRAIL=value  \n' > "$TMPENV"
OUTPUT="$(bash "$BIN" --no-inherit "$TMPENV" bash -c 'printf "%s<END>" "$TRAIL"' 2>/dev/null)" || true
if [[ "$OUTPUT" == "value  <END>" ]]; then
    pass "末尾空白を保持して後続コマンドへ渡せた"
else
    fail "末尾空白が保持されていない（出力: ${OUTPUT})"
fi
rm -f "$TMPENV"

# ---------------------------------------------------------------------------
# テスト 16: install.sh のヘルプ表示
# ---------------------------------------------------------------------------
section "16. install.sh のヘルプ表示"
OUTPUT="$(bash "$INSTALL_SCRIPT" --help 2>&1)" || true
if echo "$OUTPUT" | grep -q "使い方"; then
    pass "install.sh --help が正常に表示された"
else
    fail "install.sh --help の出力に '使い方' が含まれていない"
fi

# ---------------------------------------------------------------------------
# テスト 17: install.sh でユーザー領域へインストールできる
# ---------------------------------------------------------------------------
section "17. install.sh でユーザー領域へインストールできる"
TMP_HOME="$(mktemp -d)"
OUTPUT="$(HOME="$TMP_HOME" PATH="/usr/bin:/bin" bash "$INSTALL_SCRIPT" 2>&1)" || true
INSTALLED_BIN="${TMP_HOME}/.local/bin/kvrun"
if [[ ! -f "$INSTALLED_BIN" ]]; then
    fail "install.sh 実行後も kvrun が配置されていない（出力: ${OUTPUT})"
elif ! head -n 1 "$INSTALLED_BIN" | grep -Eq '^#!/.*/bash$'; then
    fail "インストール後の shebang が Bash の絶対パスになっていない"
elif head -n 1 "$INSTALLED_BIN" | grep -q '^#!/usr/bin/env bash$'; then
    fail "インストール後も env bash のままになっている"
elif ! echo "$OUTPUT" | grep -q "PATH に"; then
    fail "PATH 未設定時の案内が表示されていない（出力: ${OUTPUT})"
else
    RUN_OUTPUT="$(HOME="$TMP_HOME" PATH="${TMP_HOME}/.local/bin:${SYSTEM_PATH}" kvrun --help 2>&1)" || true
    if echo "$RUN_OUTPUT" | grep -q "Bash 4.3 以上"; then
        pass "install.sh で配置した kvrun を PATH 経由で実行できた"
    else
        fail "インストール後の kvrun 実行に失敗した（出力: ${RUN_OUTPUT})"
    fi
fi
rm -rf "$TMP_HOME"

# ---------------------------------------------------------------------------
# テスト 18: install.sh は古い Bash 指定を拒否
# ---------------------------------------------------------------------------
section "18. install.sh は古い Bash 指定を拒否"
TMP_INSTALL_DIR="$(mktemp -d)"
FAKE_OLD_BASH_DIR="$(mktemp -d)"
FAKE_OLD_BASH="${FAKE_OLD_BASH_DIR}/bash"
cat > "$FAKE_OLD_BASH" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-lc" ]]; then
  echo "3.2"
  exit 0
fi
exit 1
EOF
chmod +x "$FAKE_OLD_BASH"
OUTPUT="$(bash "$INSTALL_SCRIPT" --install-dir "$TMP_INSTALL_DIR" --bash-path "$FAKE_OLD_BASH" 2>&1)" || true
if echo "$OUTPUT" | grep -q "4.3 以上ではありません"; then
    pass "古い Bash を明示指定した場合に拒否できた"
else
    fail "古い Bash の拒否に失敗した（出力: ${OUTPUT})"
fi
rm -rf "$TMP_INSTALL_DIR" "$FAKE_OLD_BASH_DIR"

# ---------------------------------------------------------------------------
# テスト 19: install.sh は既存の無関係なファイルを保護する
# ---------------------------------------------------------------------------
section "19. install.sh は既存の無関係なファイルを保護する"
TMP_INSTALL_DIR="$(mktemp -d)"
printf '#!/usr/bin/env bash\necho unrelated\n' > "${TMP_INSTALL_DIR}/kvrun"
chmod +x "${TMP_INSTALL_DIR}/kvrun"
OUTPUT="$(bash "$INSTALL_SCRIPT" --install-dir "$TMP_INSTALL_DIR" 2>&1)" || true
if echo "$OUTPUT" | grep -q "既存ファイルを保護"; then
    pass "無関係な既存ファイルを上書きせず保護できた"
else
    fail "既存ファイル保護に失敗した（出力: ${OUTPUT})"
fi
rm -rf "$TMP_INSTALL_DIR"

# ---------------------------------------------------------------------------
# テスト 20: kvrun のバージョン表示
# ---------------------------------------------------------------------------
section "20. kvrun のバージョン表示"
OUTPUT="$(bash "$BIN" --version 2>&1)" || true
if [[ "$OUTPUT" == "kvrun 0.1.0" ]]; then
    pass "--version で期待したバージョンを表示できた"
else
    fail "--version の出力が想定外（出力: ${OUTPUT})"
fi

OUTPUT="$(bash "$BIN" -v 2>&1)" || true
if [[ "$OUTPUT" == "kvrun 0.1.0" ]]; then
    pass "-v でも期待したバージョンを表示できた"
else
    fail "-v の出力が想定外（出力: ${OUTPUT})"
fi

# ---------------------------------------------------------------------------
# テスト結果サマリー
# ---------------------------------------------------------------------------
echo
echo "=============================="
if [[ "$FAILED" -eq 0 ]]; then
    echo "✅ 全テスト合格"
    exit 0
else
    echo "❌ ${FAILED} 件のテストが失敗しました"
    exit 1
fi
