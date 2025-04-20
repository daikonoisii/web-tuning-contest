include .env

.PHONY: init_mac generate-deploy

init_develop_lambda:
	cd ./lighthouse-flows-generator && npm install && npm run build

build_lighthouse_lambda:
	@echo "🔧 Building Lambda with serverless-esbuild..."
	cd ./lighthouse-flows-generator && export $$(cat ../.env | xargs) && npx serverless package
	@echo "✅ Build complete. Output in .serverless/"

push_lighthouse_lambda:
	@echo "🚀 Deploying to AWS (dev stage)..."
	cd ./lighthouse-flows-generator && AWS_PROFILE=admin npx serverless deploy --stage dev
	@echo "✅ Deployment complete."

clean_lighthouse_lambda:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf ./lighthouse-flows-generator/.serverless
	rm -rf ./lighthouse-flows-generator/node_modules
	rm -f ./lighthouse-flows-generator/package-lock.json
	@echo "✅ Cleaned."

invoke_lighthouse_lambda:
	@echo "🚀 Invoking Lambda function runLighthouse-dev via AWS CLI..."
	cd lighthouse-flows-generator && \
	echo "$$EVENT_JSON" > event.json && \
	AWS_PROFILE=admin aws lambda invoke \
		--function-name run-lighthouse \
		--region $(AWS_REGION) \
		--payload fileb://event.json \
		output.json && \
	cat output.json && \
	rm event.json
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
