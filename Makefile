include .env

.PHONY: init_mac generate-deploy

init_mac:
	bash -c "brew install gettext && brew link --force gettext && which envsubst && envsubst --version"
	git checkout main
	git pull
	@if git ls-remote --exit-code --heads origin $(STUDENT_ID)/main; then \
		git switch $(STUDENT_ID)/main; \
	elif git show-ref --quiet refs/heads/$(STUDENT_ID)/main; then \
		git switch $(STUDENT_ID)/main; \
	else \
		git switch -c $(STUDENT_ID)/main; \
	fi

generate-deploy:
	set -o allexport && source .env && envsubst < .github/workflows/deploy.template.yml > .github/workflows/deploy.yml
	set -o allexport && source .env && envsubst < .github/ecs/task-def.template.json > .github/ecs/task-def.json
