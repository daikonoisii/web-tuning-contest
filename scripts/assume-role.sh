#!/bin/bash

set -e

# 利用法
usage() {
  echo "Usage: ./assume-role.sh --role-name <role-name> --profile <profile-name>" >&2
  echo "Available roles:" >&2
  jq -r 'keys[]' ./assume-role-config.json >&2
  exit 1
}

# デフォルト値
ROLE_NAME=""
PROFILE="default"

# 引数パース
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --role-name) ROLE_NAME="$2"; shift ;;
    --profile) PROFILE="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

# バリデーション
if [[ -z "$ROLE_NAME" ]]; then
  echo "❌ --role-name is required"
  usage
  exit 1
fi


if [ -z "$ROLE_NAME" ]; then
  usage
fi

CONFIG_FILE="./assume-role-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found." >&2
  exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "Error: 'jq' command not found. Please install jq." >&2
  exit 1
fi

ROLE_ARN=$(jq -r --arg role "$ROLE_NAME" '.[$role].arn' "$CONFIG_FILE")
if [ "$ROLE_ARN" == "null" ]; then
  echo "Error: Role '$ROLE_NAME' not found in $CONFIG_FILE" >&2
  usage
fi

SESSION_NAME="${USER:-cli}-$(date +%Y%m%d%H%M%S)"

echo "Assuming role: $ROLE_NAME ($ROLE_ARN)" >&2
echo "Session name: $SESSION_NAME" >&2

CREDS=$(AWS_PROFILE=$PROFILE aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "$SESSION_NAME" \
  --output json)

ACCESS_KEY=$(echo "$CREDS" | jq -r '.Credentials.AccessKeyId')
SECRET_KEY=$(echo "$CREDS" | jq -r '.Credentials.SecretAccessKey')
SESSION_TOKEN=$(echo "$CREDS" | jq -r '.Credentials.SessionToken')

export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_SESSION_TOKEN=$SESSION_TOKEN

echo "✅ Successfully assumed role '$ROLE_NAME'." >&2
echo "You can now run AWS CLI commands with this session." >&2

