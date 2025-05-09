ifneq ($(filter create-ecr-repository,$(MAKECMDGOALS)),)
  # create-ecr-repositoryならparticipant 用を読み込む
  -include .env.participant
else
  # admin 用を読み込む
  include .env.admin
endif

include .env

.PHONY: init_mac generate-deploy

init_develop_lambda:
	cd ./lighthouse-flows-generator && npm install && npm run build

build_lighthouse_lambda:
	@echo "🔧 Building Lambda with serverless-esbuild..."
	cd ./lighthouse-flows-generator && export $$(cat ../.env | xargs) && npx serverless package
	@echo "✅ Build complete. Output in .serverless/"

STAGE ?= dev

push_lighthouse_lambda:
	@echo "🚀 Deploying to AWS ($(STAGE) stage)..."
	@bash -c '\
		. ./scripts/assume-role.sh \
			--role-name $(LIGHTHOUSE_LAMBDA_ROLE_NAME) \
			--profile admin; \
		ENV_VARS="$$ENV_VARS \
			AWS_REGION=$(MY_AWS_REGION) \
			MY_AWS_REGION=$(MY_AWS_REGION) \
			S3_BUCKET_NAME=$(S3_BUCKET_NAME) \
			AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) \
			LIGHTHOUSE_FUNCTION_NAME=$(LIGHTHOUSE_FUNCTION_NAME) \
			LIGHTHOUSE_FUNCTION_NAME=$(LIGHTHOUSE_FUNCTION_NAME) \
			AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID \
			AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY \
			AWS_SESSION_TOKEN=$$AWS_SESSION_TOKEN"; \
		cd ./lighthouse-flows-generator; \
		npm run build; \
		env $$ENV_VARS npx serverless print; \
		env $$ENV_VARS npx serverless deploy --stage $(STAGE) '\
	@echo "✅ Deployment complete."

clean_lighthouse_lambda:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf ./lighthouse-flows-generator/.serverless
	rm -rf ./lighthouse-flows-generator/node_modules
	rm -f ./lighthouse-flows-generator/package-lock.json
	@echo "✅ Cleaned."

invoke_lighthouse_lambda:
	@echo "🚀 Invoking Lambda function runLighthouse-dev via AWS CLI..."
	@bash -c '\
		. ./scripts/assume-role.sh \
			--role-name $(LIGHTHOUSE_LAMBDA_ROLE_NAME) \
			--profile admin; \
		cd lighthouse-flows-generator; \
		AWS_PROFILE=admin aws lambda invoke \
			--function-name $(LIGHTHOUSE_FUNCTION_NAME) \
			--region $(MY_AWS_REGION) \
			--cli-binary-format raw-in-base64-out \
			--payload fileb://payload.json \
			--cli-read-timeout 660 \
			output.json; \
		cat output.json;'
	@echo "✅ Lambda invocation complete."

init_mac:
	bash -c "\
	  brew install gettext && \
	  brew install jq && \
	  brew link --force gettext && \
	  which envsubst && envsubst --version && \
	  jq --version"
	cd ./work_space/$(REPOSITORY_NAME); \
	git stash --include-untracked; \
	git checkout main; \
	git pull; \
	if git ls-remote --exit-code --heads origin $(STUDENT_ID)/main; then \
		git switch $(STUDENT_ID)/main; \
	elif git show-ref --quiet refs/heads/$(STUDENT_ID)/main; then \
		git switch $(STUDENT_ID)/main; \
	else \
		git switch -c $(STUDENT_ID)/main; \
	fi; \
	mkdir -p .github/workflows; \
	set -o allexport && source ../../.env && envsubst < ../../.github/workflows/deploy.yml.copy  > ./.github/workflows/deploy.yml; \
	git add ./.github/workflows/deploy.yml; \
	git commit -m "feat: :sparkles: create github action branch $(STUDENT_ID)/main"; \
	git push -u origin $(STUDENT_ID)/main
	$(MAKE) create-ecr-repository
	@echo "✅ finish"

init_aws:
	./scripts/aws_login.sh $(ENV)

init_admin:
	brew install gh
	./scripts/sync_github_secrets.sh -r ${LIGHTHOUSE_ORG}/${LIGHTHOUSE_REPOSITORY_NAME} -f ./.env.github.secrets.lighthouse
	./scripts/sync_github_secrets.sh -r ${WORK_SPACE_ORG}/${WORK_SPACE_REPOSITORY_NAME} -f ./.env.github.secrets.work_space
	$(MAKE) create-oidc-provider
	$(MAKE) create-ecs-cluster

thumbprint:
	@echo "→ $(OIDC_HOST) の証明書 thumbprint を取得中..." >&2
	@openssl s_client \
		-connect $(OIDC_HOST):443 \
		-servername $(OIDC_HOST) \
		-showcerts </dev/null 2>/dev/null \
	| openssl x509 -noout -fingerprint -sha1 \
	| sed 's/^.*=//' \
	| sed 's/://g' \
	| tr '[:upper:]' '[:lower:]'

create-oidc-provider:
	@THUMB=$$(make thumbprint); \
	echo "→ AWS に OIDC プロバイダーを作成 (URL=https://$(OIDC_HOST), thumbprint=$$THUMB)" >&2; \
	. ./scripts/assume-role.sh \
			--role-name $(OIDC_ROLE_NAME) \
			--profile admin; \
	aws iam create-open-id-connect-provider \
	  --url "https://$(OIDC_HOST)" \
	  --thumbprint-list "$$THUMB" \
	  --client-id-list "$(CLIENT_ID)"

create-ecr-repository:
	. ./scripts/assume-role.sh \
			--role-name $(ECR_ROLE_NAME) \
			--profile participant; \
	aws ecr create-repository --repository-name $(ECR_REPOSITORY)-$(STUDENT_ID) --region ap-northeast-1

create-ecs-cluster:
	. ./scripts/assume-role.sh \
		--role-name $(ECS_ROLE_NAME) \
		--profile admin; \
	if aws ecs describe-clusters \
	      --clusters $(ECS_CLUSTER) \
	      --region $(MY_AWS_REGION) \
	      --query "clusters[?status=='ACTIVE'].clusterName" \
	      --output text 2>/dev/null \
	      | grep -q $(ECS_CLUSTER); then \
	  echo "✔ Cluster '$(ECS_CLUSTER)' already exists."; \
	else \
	  echo "🔧 Creating ECS cluster '$(ECS_CLUSTER)'..."; \
	  aws ecs create-cluster \
	    --cluster-name $(ECS_CLUSTER) \
	    --capacity-providers FARGATE \
	    --region $(MY_AWS_REGION); \
	  echo "✅ Cluster created."; \
	fi

test:
	. ./scripts/assume-role.sh \
		--role-name $(ECS_ROLE_NAME) \
		--profile admin; \
	aws ecs describe-clusters \
		--clusters $(ECS_CLUSTER) \
		--region $(MY_AWS_REGION) \
		--query "clusters[?status=='ACTIVE'].clusterName" \
		--output text