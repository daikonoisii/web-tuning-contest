SHELL := /bin/bash

ifneq ($(filter create-ecr-repository \
				create-ecs-service \
				init_mac \
				create-logs-group \
				get_aws_parameters \
				register-task-definition,$(MAKECMDGOALS)),)
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
			AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID \
			AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY \
			SLACK_BOT_TOKEN=$(SLACK_BOT_TOKEN) \
			SLACK_SIGNING_SECRET=$(SLACK_SIGNING_SECRET) \
			MAPPING_S3_KEY=$(MAPPING_S3_KEY) \
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
	if ! RESPONSE=$$(make --no-print-directory -s create-ecr-repository 2>&1); then \
	  if echo "$$RESPONSE" | grep -q 'RepositoryAlreadyExistsException'; then \
	    echo "ECRリポジトリは既に存在しています。処理を継続します。"; \
	  else \
	    echo "$$RESPONSE"; \
	    exit 1; \
	  fi; \
	fi; \
	make --no-print-directory -s  create-logs-group
	make --no-print-directory -s register-task-definition
	SD_SERVICE_ARN=($$(make --no-print-directory -s register-sd-service)); \
	VARS=$$(make --no-print-directory -s get_aws_parameters); \
	SG_ECS=$$(echo $$VARS | jq -r '.SG_ECS') \
	SG_LAMBDA=$$(echo $$VARS | jq -r '.SG_LAMBDA') \
	SUBNET1_ID=$$(echo $$VARS | jq -r '.SUBNET1_ID') \
	SUBNET2_ID=$$(echo $$VARS | jq -r '.SUBNET2_ID') \
	SD_SERVICE_ARN=$$SD_SERVICE_ARN \
	make --no-print-directory -s create-ecs-service
	@echo "✅ finish"

init_aws:
	./scripts/aws_login.sh $(ENV)

init_admin:
	brew install gh
	brew install --cask session-manager-plugin
	./scripts/sync_github_secrets.sh -r ${LIGHTHOUSE_ORG}/${LIGHTHOUSE_REPOSITORY_NAME} -f ./.env.github.secrets.lighthouse
	./scripts/sync_github_secrets.sh -r ${WORK_SPACE_ORG}/${WORK_SPACE_REPOSITORY_NAME} -f ./.env.github.secrets.work_space
	if ! RESPONSE=$$(make --no-print-directory -s create-oidc-provider 2>&1); then \
	  if echo "$$RESPONSE" | grep -q 'EntityAlreadyExists'; then \
	    echo "OIDCプロバイダーは既に存在しています。処理を継続します。"; \
	  else \
	    echo "$$RESPONSE"; \
	    exit 1; \
	  fi; \
	fi; \
	VARS=($$(MAKE --no-print-directory -s create-vpc)); \
	VPC_ID=$${VARS[0]}; \
	SUBNET1_ID=$${VARS[1]}; \
	SUBNET2_ID=$${VARS[2]}; \
	VARS=($$( \
		VPC_ID=$${VPC_ID} \
		make --no-print-directory -s create-security-group)); \
	SG_LAMBDA=$${VARS[0]}; \
	SG_ECS=$${VARS[1]}; \
	SG_ECR=$${VARS[2]}; \
	SG_SSM=$${VARS[3]}; \
	SG_LAMBDA=$$SG_LAMBDA \
	SG_ECS=$$SG_ECS \
	SG_ECR_ID=$$SG_ECR \
	SG_SSM=$$SG_SSM \
	make --no-print-directory -s create-security-rule; \
	if ! RESPONSE=$$( \
		VPC_ID=$$VPC_ID \
		SUBNET1_ID=$$SUBNET1_ID \
		SUBNET2_ID=$$SUBNET2_ID \
		SG_ECR_ID=$$SG_ECR \
		SG_SSM_ID=$$SG_SSM \
		make --no-print-directory -s create-endpoint 2>&1); then \
		if echo "$$RESPONSE" | grep -q 'AlreadyExists'; then \
	    	echo "エンドポイントは既に存在しています。処理を継続します。"; \
		else \
	    	echo "$$RESPONSE"; \
	    	exit 1; \
		fi; \
	fi; \
	VPC_ID=$$VPC_ID \
	make --no-print-directory -s create-sd-namespace; \
	VPC_ID=$$VPC_ID \
	SUBNET1_ID=$$SUBNET1_ID \
	SUBNET2_ID=$$SUBNET2_ID \
	SG_LAMBDA=$$SG_LAMBDA \
	SG_ECS=$$SG_ECS \
	make --no-print-directory -s push_aws_parameters; \
	$(MAKE) create-ecs-cluster
	. ./scripts/assume-role.sh \
		--role-name $(MAPPING_ROLE_NAME) \
		--profile admin; \
	AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID \
	AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY \
	AWS_SESSION_TOKEN=$$AWS_SESSION_TOKEN \
	npx ts-node ./lighthouse-flows-generator/src/sync_slack_mapping.ts

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
	aws ecr create-repository --repository-name $(ECR_REPOSITORY)-$(STUDENT_ID) --region $(MY_AWS_REGION)

create-ecs-cluster:
	. ./scripts/assume-role.sh \
		--role-name $(ECS_ADMIN_ROLE_NAME) \
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

create-vpc:
	. ./scripts/assume-role.sh \
			--role-name $(VPC_ROLE_NAME) \
			--profile admin; \
	VPC_ID=$$(aws ec2 create-vpc \
		--cidr-block $(VPC_CIDR) \
		--region $(MY_AWS_REGION) \
		--query 'Vpc.VpcId' \
		--output text); \
	aws ec2 modify-vpc-attribute \
		--vpc-id $$VPC_ID \
		--enable-dns-support '{"Value": true}'; \
	aws ec2 modify-vpc-attribute \
		--vpc-id $$VPC_ID \
		--enable-dns-hostnames '{"Value":true}'; \
	SUBNET1_ID=$$(aws ec2 create-subnet --vpc-id $$VPC_ID --cidr-block $(SUBNET1_CIDR) \
				--availability-zone $(AZ1) --query 'Subnet.SubnetId' --output text); \
	SUBNET2_ID=$$(aws ec2 create-subnet --vpc-id $$VPC_ID --cidr-block $(SUBNET2_CIDR) \
				--availability-zone $(AZ2) --query 'Subnet.SubnetId' --output text); \
	echo "$$VPC_ID $$SUBNET1_ID $$SUBNET2_ID"

create-security-group:
	. ./scripts/assume-role.sh \
		--role-name $(VPC_ROLE_NAME) \
		--profile admin; \
	SG_LAMBDA=$$(aws ec2 create-security-group \
		--group-name $(SG_LAMBDA_NAME) \
		--description "Lambda outbound to ECS only" \
		--vpc-id $$VPC_ID \
		--query 'GroupId' \
		--output text); \
	SG_ECS=$$(aws ec2 create-security-group \
		--group-name $(SG_ECS_NAME) \
		--description "ECS inbound from Lambda" \
		--vpc-id $$VPC_ID \
		--query 'GroupId' \
		--output text); \
	SG_ECR_ID=$$(aws ec2 create-security-group \
		--group-name $(SG_ECR_NAME) \
		--description "ECR VPC endpoint SG" \
		--vpc-id $$VPC_ID \
		--query 'GroupId' \
		--output text); \
	SG_SSM_ID=$$(aws ec2 create-security-group \
		--group-name $(SG_SSM_NAME) \
		--description "SSM Interface Endpoint SG" \
		--vpc-id $$VPC_ID \
		--query GroupId \
		--output text); \
	echo "$$SG_LAMBDA $$SG_ECS $$SG_ECR_ID $$SG_SSM_ID"

create-security-rule:
	. ./scripts/assume-role.sh \
		--role-name $(VPC_ROLE_NAME) \
		--profile admin; \
	aws ec2 authorize-security-group-ingress \
		--group-id $$SG_ECS \
		--protocol tcp \
		--port $(APP_PORT) \
		--source-group $$SG_LAMBDA; \
	aws ec2 authorize-security-group-ingress \
		--group-id $$SG_ECR_ID \
		--protocol tcp \
		--port 443 \
		--source-group $$SG_ECS; \
	aws ec2 authorize-security-group-ingress \
		--group-id $$SG_SSM \
		--protocol tcp \
		--port 443 \
		--source-group $$SG_ECS; \

register-task-definition:
	set -o allexport && source ./.env.participant && source ./.env && envsubst < .github/ecs/task-def.template.json > ./.github/ecs/task-def.json
	. ./scripts/assume-role.sh \
		--role-name $(ECS_ROLE_NAME) \
		--profile participant; \
	aws ecs register-task-definition \
		--cli-input-json file://.github/ecs/task-def.json \
		--query 'taskDefinition.taskDefinitionArn' \
		--output text \
		--region ${MY_AWS_REGION};
	rm ./.github/ecs/task-def.json

push_aws_parameters:
	. ./scripts/assume-role.sh \
			--role-name $(PUSH_PARAMETER_ROLE_NAME) \
			--profile admin; \
	TMP_ENV=$$(mktemp); \
	echo "VPC_ID=$$VPC_ID"                 >> $$TMP_ENV; \
	echo "SUBNET1_ID=$$SUBNET1_ID"         >> $$TMP_ENV; \
	echo "SUBNET2_ID=$$SUBNET2_ID"         >> $$TMP_ENV; \
	echo "SG_LAMBDA=$$SG_LAMBDA"           >> $$TMP_ENV; \
	echo "SG_ECS=$$SG_ECS"         		   >> $$TMP_ENV; \
	env AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID \
	    AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY \
	    AWS_SESSION_TOKEN=$$AWS_SESSION_TOKEN \
	    ./scripts/push_aws_parameters.sh -f $$TMP_ENV --prefix /${PARAMETERS_PREFIX}; \
	rm $$TMP_ENV; \

get_aws_parameters:
	. ./scripts/assume-role.sh \
		--role-name $(GET_PARAMETER_ROLE_NAME) \
		--profile participant; \
	VARS=$$(aws ssm get-parameters-by-path \
		--path "/${PARAMETERS_PREFIX}" \
		--with-decryption \
		--recursive \
		--output json); \
	output="{"; \
	first=true; \
	tmpfile=$$(mktemp); \
	echo "$$VARS" | jq -c '.Parameters[]' > $$tmpfile; \
	while read -r row; do \
		name=$$(echo $$row | jq -r '.Name' | sed 's|.*/||'); \
		value=$$(echo $$row | jq -r '.Value'); \
		if [ "$$first" = true ]; then \
			first=false; \
		else \
			output="$$output,"; \
		fi; \
		output="$$output\"$$name\":\"$$value\""; \
	done < $$tmpfile; \
	rm $$tmpfile; \
	output="$$output}"; \
	echo $$output

create-ecs-service:
	. ./scripts/assume-role.sh \
		--role-name $(ECS_ROLE_NAME) \
		--profile participant; \
	aws ecs create-service \
		--cluster $(ECS_CLUSTER) \
		--region $(MY_AWS_REGION) \
		--service-name $(ECS_SERVICE)-$(STUDENT_ID) \
		--task-definition ${FAMILY_NAME}-$(STUDENT_ID) \
		--desired-count 1 \
		--launch-type FARGATE \
		--service-registries registryArn=$$SD_SERVICE_ARN \
		--enable-execute-command \
		--deployment-configuration "minimumHealthyPercent=0,maximumPercent=100" \
		--network-configuration "awsvpcConfiguration={ \
			subnets=[$$SUBNET1_ID,$$SUBNET2_ID], \
			securityGroups=[$$SG_ECS], \
			assignPublicIp=DISABLED \
		}"; \
	aws lambda update-function-configuration \
		--function-name $(LIGHTHOUSE_FUNCTION_NAME) \
		--vpc-config "SubnetIds=$$SUBNET1_ID,$$SUBNET2_ID,SecurityGroupIds=$$SG_LAMBDA"

create-endpoint:
	. ./scripts/assume-role.sh \
		--role-name $(VPC_ENDPOINT_ROLE_NAME) \
		--profile admin; \
	aws ec2 create-vpc-endpoint \
		--vpc-id $$VPC_ID \
		--vpc-endpoint-type Interface \
		--service-name com.amazonaws.$(MY_AWS_REGION).ecr.api \
		--subnet-ids $$SUBNET1_ID $$SUBNET2_ID \
		--security-group-ids $$SG_ECR_ID \
		--private-dns-enabled; \
  	aws ec2 create-vpc-endpoint \
		--vpc-id $$VPC_ID \
		--vpc-endpoint-type Interface \
		--service-name com.amazonaws.$(MY_AWS_REGION).ecr.dkr \
		--subnet-ids $$SUBNET1_ID $$SUBNET2_ID \
		--security-group-ids $$SG_ECR_ID \
		--private-dns-enabled; \
  	RTB_IDS=$$(aws ec2 describe-route-tables \
  		--filters \
    	"Name=vpc-id,Values=$$VPC_ID" \
    	"Name=association.main,Values=true" \
  		--query 'RouteTables[].RouteTableId' --output text); \
	aws ec2 create-vpc-endpoint \
		--vpc-id $$VPC_ID \
		--vpc-endpoint-type Gateway \
		--service-name com.amazonaws.$(MY_AWS_REGION).s3 \
		--route-table-ids $$RTB_IDS; \
	aws ec2 create-vpc-endpoint \
		--vpc-id $$VPC_ID \
		--vpc-endpoint-type Interface \
		--service-name com.amazonaws.${MY_AWS_REGION}.logs \
		--subnet-ids $$SUBNET1_ID $$SUBNET2_ID \
		--security-group-ids $$SG_ECR_ID \
		--private-dns-enabled; \
	for svc in ssm ssmmessages ec2messages ; do \
		aws ec2 create-vpc-endpoint \
			--vpc-id $$VPC_ID \
			--service-name com.amazonaws.$(MY_AWS_REGION).$$svc \
			--vpc-endpoint-type Interface \
			--subnet-ids $$SUBNET1_ID $$SUBNET2_ID \
			--security-group-ids $$SG_SSM_ID \
			--private-dns-enabled; \
	done

create-logs-group:
	echo "✅$(LOGS_GROUP_ROLE_NAME)"
	. ./scripts/assume-role.sh \
			--role-name $(LOGS_GROUP_ROLE_NAME) \
			--profile participant; \
	aws logs create-log-group \
		--log-group-name "/ecs/work-space-${STUDENT_ID}" \
		--region "${MY_AWS_REGION}"

create-sd-namespace:
	. ./scripts/assume-role.sh \
		--role-name $(CLOUDMAP_ROLE_NAME) \
		--profile admin; \
	OP_ID=$$(aws servicediscovery create-private-dns-namespace \
		--name "$(SD_NAMESPACE)" \
		--vpc "$$VPC_ID" \
		--description "Service Discovery namespace for Lighthouse targets" \
		--creator-request-id "$$(date +%s)" \
		--query "OperationId" \
		--output text); \
	echo "✅ Namespace creation kicked off, OperationId=$$OP_ID"; \
	STATUS=""; \
	until [ "$$STATUS" = "SUCCESS" ]; do \
		echo "⏳ Waiting for namespace to be ACTIVE (current: $$STATUS)…"; \
		sleep 2; \
		STATUS=$$(aws servicediscovery get-operation --operation-id $$OP_ID \
			--query "Operation.Status" --output text); \
	done; \
	echo "✅ Namespace is now ACTIVE!"

register-sd-service:
	. ./scripts/assume-role.sh \
		--role-name $(CLOUDMAP_ROLE_NAME) \
		--profile participant; \
	NAMESPACE_ID=$$(aws servicediscovery list-namespaces \
	    --filters "Name=TYPE,Values=DNS_PRIVATE" "Name=NAME,Values=$(SD_NAMESPACE)" \
	    --query "Namespaces[0].Id" --output text); \
	aws servicediscovery create-service \
		--name "$(ECS_SERVICE)-$(STUDENT_ID)" \
		--namespace-id $$NAMESPACE_ID \
		--description "Service Discovery for $(ECS_SERVICE)-$(STUDENT_ID)" \
		--dns-config "NamespaceId=$$NAMESPACE_ID,RoutingPolicy=MULTIVALUE,DnsRecords=[{Type=A,TTL=60}]" \
		--query "Service.Arn" --output text \

start-session:
	. ./scripts/assume-role.sh \
		--role-name $(CONNECT_ECS) \
		--profile admin; \
	TASK_ARN=$$(aws ecs list-tasks \
		--cluster $(ECS_CLUSTER) \
		--service-name $(ECS_SERVICE)-$(STUDENT_ID) \
		--desired-status RUNNING \
		--query 'taskArns[0]' \
		--output text); \
	TASK_ID=$${TASK_ARN##*/}; \
	RUNTIME_ID=$$(aws ecs describe-tasks \
		--cluster ${ECS_CLUSTER} \
		--tasks "$$TASK_ID" \
		--query 'tasks[0].containers[?name==`web-server`].runtimeId' \
		--output text); \
	aws ssm start-session \
		--target ecs:$(ECS_CLUSTER)_$${TASK_ID}_$${RUNTIME_ID} \
		--document-name  AWS-StartPortForwardingSessionToRemoteHost \
		--parameters '{"host":["127.0.0.1"],"portNumber":["$(APP_PORT)"],"localPortNumber":["8080"]}'

ecs-exec:
	. ./scripts/assume-role.sh \
		--role-name $(CONNECT_ECS) \
		--profile admin; \
	TASK_ARN=$$(aws ecs list-tasks \
		--cluster $(ECS_CLUSTER) \
		--service-name $(ECS_SERVICE)-$(STUDENT_ID) \
		--desired-status RUNNING \
		--query 'taskArns[0]' \
		--output text); \
	TASK_ID=$${TASK_ARN##*/}; \
	aws ecs execute-command \
		--cluster lighthouse-cluster \
		--task arn:aws:ecs:ap-northeast-1:$(AWS_ACCOUNT_ID):task/$(ECS_CLUSTER)/$$TASK_ID \
		--container web-server \
		--interactive \
		--command "/bin/sh"
