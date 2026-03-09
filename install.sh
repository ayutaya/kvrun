#!/usr/bin/env bash
# kvrun をユーザー領域へ安全にインストールする

set -euo pipefail

readonly APP_NAME="kvrun"
readonly MIN_BASH_MAJOR=4
readonly MIN_BASH_MINOR=3
readonly DEFAULT_INSTALL_DIR="${HOME}/.local/bin"

log_info() {
    echo "[${APP_NAME}] $*" >&2
}

log_error() {
    echo "[${APP_NAME}] エラー: $*" >&2
}

usage() {
    cat >&2 <<EOF
使い方: bash install.sh [オプション]

オプション:
  --install-dir <ディレクトリ>   インストール先を指定（既定: ${DEFAULT_INSTALL_DIR}）
  --bash-path <bash 実行ファイル> 実行時に固定する Bash を指定
  --force                       既存の ${APP_NAME} を上書き
  -h, --help                    このヘルプを表示

仕様:
  - 既定では sudo を使わず、ユーザー領域へインストールします
  - ${APP_NAME} 本体の実行には Bash ${MIN_BASH_MAJOR}.${MIN_BASH_MINOR} 以上が必要です
  - インストール時に利用する Bash は絶対パスで固定します
EOF
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

bash_version_of() {
    local candidate="$1"

    [[ -x "$candidate" ]] || return 1
    "$candidate" -lc 'printf "%s.%s\n" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null
}

bash_is_supported() {
    local candidate="$1"
    local version=""
    local major=""
    local minor=""

    version="$(bash_version_of "$candidate")" || return 1
    major="${version%%.*}"
    minor="${version#*.}"

    [[ "$major" =~ ^[0-9]+$ ]] || return 1
    [[ "$minor" =~ ^[0-9]+$ ]] || return 1

    if (( major > MIN_BASH_MAJOR )); then
        return 0
    fi

    if (( major == MIN_BASH_MAJOR && minor >= MIN_BASH_MINOR )); then
        return 0
    fi

    return 1
}

find_supported_bash() {
    local requested_path="${1:-}"
    local command_bash=""
    local candidate=""
    local -a candidates=()

    if [[ -n "$requested_path" ]]; then
        if bash_is_supported "$requested_path"; then
            printf '%s\n' "$requested_path"
            return 0
        fi

        log_error "指定された Bash は ${MIN_BASH_MAJOR}.${MIN_BASH_MINOR} 以上ではありません: ${requested_path}"
        return 1
    fi

    if command_bash="$(command -v bash 2>/dev/null)"; then
        candidates+=("/opt/homebrew/bin/bash" "/usr/local/bin/bash" "$command_bash" "/bin/bash" "/usr/bin/bash")
    else
        candidates+=("/opt/homebrew/bin/bash" "/usr/local/bin/bash" "/bin/bash" "/usr/bin/bash")
    fi

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if bash_is_supported "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    log_error "Bash ${MIN_BASH_MAJOR}.${MIN_BASH_MINOR} 以上が見つかりません。"
    log_error "WSL2(Ubuntu) では bash を更新し、macOS では Homebrew などで新しい bash を導入してください。"
    return 1
}

path_contains_dir() {
    local target_dir="$1"
    local entry=""
    local normalized_target=""
    local IFS=':'

    normalized_target="$(trim "$target_dir")"
    for entry in ${PATH:-}; do
        if [[ "$(trim "$entry")" == "$normalized_target" ]]; then
            return 0
        fi
    done

    return 1
}

script_contains_kvrun_marker() {
    local file_path="$1"

    [[ -f "$file_path" ]] || return 1
    grep -q '^# kvrun - Azure Key Vault から環境変数を取得して後続コマンドを起動するラッパースクリプト$' "$file_path"
}

install_dir="${KVRUN_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
selected_bash_path="${KVRUN_BASH_PATH:-}"
force_overwrite=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)
            if [[ $# -lt 2 ]]; then
                log_error "--install-dir にはディレクトリを指定してください。"
                exit 1
            fi
            install_dir="$2"
            shift 2
            ;;
        --bash-path)
            if [[ $# -lt 2 ]]; then
                log_error "--bash-path には Bash 実行ファイルを指定してください。"
                exit 1
            fi
            selected_bash_path="$2"
            shift 2
            ;;
        --force)
            force_overwrite=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "不明なオプション: $1"
            usage
            exit 1
            ;;
    esac
done

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_SCRIPT="${REPO_ROOT}/bin/kvrun"

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
    log_error "インストール元スクリプトが見つかりません: ${SOURCE_SCRIPT}"
    exit 1
fi

if [[ ! -r "$SOURCE_SCRIPT" ]]; then
    log_error "インストール元スクリプトを読み取れません: ${SOURCE_SCRIPT}"
    exit 1
fi

resolved_bash_path="$(find_supported_bash "$selected_bash_path")" || exit 1
readonly resolved_bash_path

install_dir="${install_dir%/}"
if [[ -z "$install_dir" ]]; then
    log_error "インストール先ディレクトリが不正です。"
    exit 1
fi

target_path="${install_dir}/${APP_NAME}"
readonly target_path

if [[ -e "$install_dir" && ! -d "$install_dir" ]]; then
    log_error "インストール先がディレクトリではありません: ${install_dir}"
    exit 1
fi

if [[ -e "$target_path" && "$force_overwrite" != true ]]; then
    if ! script_contains_kvrun_marker "$target_path"; then
        log_error "既存ファイルを保護するため上書きを中止しました: ${target_path}"
        log_error "上書きする場合は内容を確認したうえで --force を指定してください。"
        exit 1
    fi
fi

if [[ ! -d "$install_dir" ]]; then
    if ! mkdir -p "$install_dir" 2>/dev/null; then
        log_error "インストール先ディレクトリを作成できません: ${install_dir}"
        exit 1
    fi
    chmod 700 "$install_dir" 2>/dev/null || true
fi

if [[ ! -w "$install_dir" ]]; then
    log_error "インストール先ディレクトリに書き込めません: ${install_dir}"
    exit 1
fi

if ! temp_file="$(mktemp "${install_dir}/.${APP_NAME}.XXXXXX" 2>/dev/null)"; then
    log_error "一時ファイルの作成に失敗しました: ${install_dir}"
    exit 1
fi
cleanup() {
    rm -f "$temp_file"
}
trap cleanup EXIT

{
    printf '#!%s\n' "$resolved_bash_path"
    tail -n +2 "$SOURCE_SCRIPT"
} > "$temp_file" 2>/dev/null || {
    log_error "インストール用ファイルの生成に失敗しました。"
    exit 1
}

if ! chmod 700 "$temp_file" 2>/dev/null; then
    log_error "インストール用ファイルの権限設定に失敗しました。"
    exit 1
fi

if ! mv -f "$temp_file" "$target_path" 2>/dev/null; then
    log_error "インストール先への配置に失敗しました: ${target_path}"
    exit 1
fi

trap - EXIT

log_info "インストール完了: ${target_path}"
log_info "実行時に使用する Bash: ${resolved_bash_path}"

if path_contains_dir "$install_dir"; then
    log_info "このまま '${APP_NAME} --help' を実行できます。"
else
    log_info "PATH に ${install_dir} が含まれていません。"
    log_info "例: export PATH=\"${install_dir}:\$PATH\""
fi
