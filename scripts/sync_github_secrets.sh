#!/usr/bin/env bash
set -euo pipefail

# デフォルトの env ファイル名
ENV_FILE="../.env.github.secrets"
REPO=""

# ヘルプ表示関数
tmp_usage() {
  cat <<EOF
Usage: $0 -r owner/repo [-f env_file]

Options:
  -r  GitHub repository in owner/repo format (required)
  -f  Path to .env file (default: $ENV_FILE)
  -h  Show this help message
EOF
  exit 1
}

# 引数解析
while getopts ":r:f:h" opt; do
  case ${opt} in
    r) REPO=$OPTARG ;; 
    f) ENV_FILE=$OPTARG ;; 
    h) tmp_usage ;; 
    *) tmp_usage ;; 
  esac
done

# リポジトリ必須チェック
if [[ -z "$REPO" ]]; then
  echo "Error: repository (-r) is required."
  tmp_usage
fi

# gh CLI の存在チェック
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) not found. Please install: https://cli.github.com/"
  exit 1
fi

# 認証実行
echo "→ Authenticating with GitHub CLI..."
gh auth login --hostname github.com

# 認証状態確認
if ! gh auth status >/dev/null 2>&1; then
  echo "Error: GitHub CLI authentication failed."
  exit 1
fi

# env ファイル存在チェック
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: env file '$ENV_FILE' not found."
  exit 1
fi

echo "→ Syncing secrets from '$ENV_FILE' to '$REPO'..."
while IFS='=' read -r name value || [[ -n "$name" ]]; do
  # コメント行または空行をスキップ
  [[ "$name" =~ ^\s*# ]] && continue
  [[ -z "$name" ]] && continue

  # 前後の空白をトリム
  name=$(echo -n "$name" | xargs)
  value=$(echo -n "$value" | xargs)

  echo "  • Setting secret: $name"
  gh secret set "$name" -R "$REPO" --body "$value"
done < "$ENV_FILE"

echo "All secrets synced successfully."
