#!/usr/bin/env bash
set -euo pipefail

# デフォルト値
ENV_FILE=""
PARAM_PREFIX="/myapp"
SHOW_HELP=false

# ヘルプ関数
print_usage() {
  cat <<EOF
Usage: $0 -f <env_file> [--prefix /path/prefix]

Options:
  -f        Path to .env file (required)
  --prefix  SSM parameter path prefix (default: /myapp)
  -h        Show this help message

Example:
  $0 -f ./secrets.env --prefix /lighthouse/dev
EOF
  exit 1
}

# 引数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f)
      ENV_FILE="$2"
      shift 2
      ;;
    --prefix)
      PARAM_PREFIX="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      ;;
  esac
done

# 引数チェック
if [[ -z "$ENV_FILE" ]]; then
  echo "❌ Error: -f <env_file> is required."
  print_usage
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Error: env file not found: $ENV_FILE"
  exit 1
fi

echo "📦 Uploading parameters from: $ENV_FILE"
echo "📁 Using prefix: $PARAM_PREFIX"

while IFS='=' read -r key value || [[ -n "$key" ]]; do
  # 空行・コメント行をスキップ
  [[ "$key" =~ ^\s*# ]] && continue
  [[ -z "$key" ]] && continue

  # 空白を除去
  key=$(echo -n "$key" | xargs)
  value=$(echo -n "$value" | xargs)

  # 型判定
  if [[ "$key" == *_SECURE ]]; then
    param_key="${key%_SECURE}"
    param_type="SecureString"
  elif [[ "$value" == *,* ]]; then
    param_key="$key"
    param_type="StringList"
  else
    param_key="$key"
    param_type="String"
  fi

  # フルパス作成
  full_param_name="${PARAM_PREFIX}/${param_key}"

  echo "  → Registering: ${full_param_name} (${param_type})"

  aws ssm put-parameter \
    --name "$full_param_name" \
    --value "$value" \
    --type "$param_type" \
    --overwrite
done < "$ENV_FILE"

echo "✅ All parameters uploaded successfully."
