include .env

.PHONY: init_mac generate-deploy

init_mac:
	bash -c "brew install gettext && brew link --force gettext && which envsubst && envsubst --version"

generate-deploy:
	set -o allexport && source .env && envsubst < .github/workflows/deploy.template.yml > .github/workflows/deploy.yml
	set -o allexport && source .env && envsubst < .github/ecs/task-def.template.json > .github/ecs/task-def.json
