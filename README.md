# Web Tuning Contest

## 概要
このリポジトリでは、Web Tuning Contest（ウェブ・チューニング・コンテスト）を運営するためのインフラと自動化スクリプトをまとめています。  
コンテスト参加者がチューニングしたウェブサイトをawsで自動デプロイ、Lighthouseを用いて自動で計測・採点し、結果を集計・通知する仕組みを提供します。

主な構成要素は以下のとおりです：
- **lighthouse-flows-generator/**  
  AWS Lambda 上で動作する Node.js プロジェクト。Puppeteer と Lighthouse ユーザーフローAPI を使い、指定された URL のパフォーマンス計測を実行し、HTML／JSON レポートを生成します。
- **Makefile**  
  ローカルおよび CI/CD 環境での一連のセットアップ・ビルド・デプロイ手順をまとめた Makefile。
- **.github/**  
  GitHub Actions ワークフロー（例：プルリクエスト受信時の自動チューニングジョブ起動 など）が配置されています。
- **work_space/**  
  チューニング対象のwebサイト(リポジトリ)を配置します。参加者はここにあるコードを編集することでデプロイされるサイトに変更を加えることができます。

各ディレクトリ／ファイルは以下で詳しく説明します。

---

## ディレクトリ構成

---

## 必要要件
1. **ローカル環境**
   - macOS もしくは Linux
   - Bash（`/bin/bash` が利用できること）
   - GNU Make
   - Docker
   - Homebrew
   - AWS アカウントおよび十分な権限を持つ IAM ユーザー／ロール

---

## 環境構築

### 管理者(主催者側)
以下の手順で必要な環境を準備し、AWS へデプロイできる状態にします。

1. **リポジトリのクローン**
```bash
   git clone https://github.com/{リポジトリ}
   cd web-tuning-contest
```

### 参加者

1. **リポジトリのクローン**
```bash
   git clone https://github.com/{リポジトリ}
   cd web-tuning-contest
```
2. **envファイルを受け取る**
Slack botからenvファイルが送られてくるため、そのenvファイルをプロジェクト直下に配置
3. **awsのアカウントを設定**
以下コマンドを実行して出力に[profile participant]が含まれないことを確認。
```bash
cat ~/.aws/config
```
以下コマンドを実行して参加者用のアカウントを設定。
```bash
    make init_aws ENV=participant
```
4. **開発環境を構築**
以下コマンドを実行して環境構築
```bash
    make init_mac
```

---

## コンテストの実行方法

---

## Makefile の主なターゲット例


実際の定義は Makefile を参照してください。
---

## lighthouse-flows-generator の詳細

`lighthouse-flows-generator/` 配下では以下のような構成が想定されています。

---

## scripts ディレクトリの概要

`./scripts/assume-role.sh` を使って、必要に応じて異なる IAM ロールを引き受ける流れになっています。  
使い方例：

```bash
./scripts/assume-role.sh --role-name CreateVpcRole --profile admin
```

各スクリプトは以下のような役割は持ちます：

---

## GitHub Actions 連携例

`.github/workflows/run-tuning.yml` では、学生リポジトリの特定ブランチ（例：`STUDENT_ID/main`）にプルリクエストがマージ（クローズ）されたタイミングで、`repository_dispatch` イベントを送信し、メインのチューニングシステム側に Payload を渡して自動測定をトリガーする仕組みを実装しています。

```
```

上記のように設定することで、学生リポジトリの PR がマージされると自動的にメインリポジトリでチューニング処理が開始されます。

---

## 関連リンク

* [Lighthouse User Flows ドキュメント（英語）](https://web.dev/lighthouse-user-flows/)
* [Serverless Framework ドキュメント](https://www.serverless.com/framework/docs/)
* [AWS CLI ドキュメント](https://docs.aws.amazon.com/cli/latest/index.html)

---

以上が本リポジトリの README サンプルです。実際の運用要件に合わせて、環境変数やスクリプトの引数を調整し、独自の開発フローに最適化してください。
