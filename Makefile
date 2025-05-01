-include .env.admin
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
	git checkout main
	git pull
	@if git ls-remote --exit-code --heads origin $(STUDENT_ID)/main; then \
		git switch $(STUDENT_ID)/main; \
	elif git show-ref --quiet refs/heads/$(STUDENT_ID)/main; then \
		git switch $(STUDENT_ID)/main; \
	else \
		git switch -c $(STUDENT_ID)/main; \
	fi

init_aws:
	./scripts/aws_login.sh $(ENV)

generate-deploy:
	set -o allexport && source .env && envsubst < .github/workflows/deploy.template.yml > .github/workflows/deploy.yml
	set -o allexport && source .env && envsubst < .github/ecs/task-def.template.json > .github/ecs/task-def.json
