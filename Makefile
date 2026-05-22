.PHONY: deploy destroy audit test fmt validate

deploy:
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh

destroy:
	@chmod +x scripts/teardown.sh
	@./scripts/teardown.sh

audit:
	@python3 scripts/config_audit_agent.py || python scripts/config_audit_agent.py

test:
	@chmod +x scripts/test-api.sh
	@./scripts/test-api.sh

fmt:
	cd terraform && terraform fmt

validate:
	cd terraform && terraform init -backend=false && terraform validate
