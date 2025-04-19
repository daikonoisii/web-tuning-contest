#!/bin/bash
set -e

# $1 がなければ .env を読み込んで default として設定
if [ -z "$1" ]; then
  ENV_FILE=".env"
  PROFILE="default"
else
  ENV_FILE=".env.$1"

  # .env.xxx の xxx 部分をプロファイル名として使う
  BASENAME=$(basename "$ENV_FILE")
  if [[ "$BASENAME" =~ ^\.env\.([a-zA-Z0-9_-]+)$ ]]; then
    PROFILE="${BASH_REMATCH[1]}"
  else
    echo "❌ ファイル名は .env.xxx の形式にしてください（例: .env.admin）"
    exit 1
  fi
fi

# ファイルが存在するかチェック
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 指定された .env ファイル '$ENV_FILE' が見つかりません"
  exit 1
fi

# 環境変数を export
set -a
source "$ENV_FILE"
set +a

# aws configure に設定
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$PROFILE"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$PROFILE"
aws configure set region "$AWS_REGION" --profile "$PROFILE"
aws configure set output json --profile "$PROFILE"

echo "✅ プロファイル '$PROFILE' を設定しました（ファイル: $ENV_FILE）"

