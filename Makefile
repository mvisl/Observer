.PHONY: build test app run inspect diagnose install-login uninstall-login github-private github-brain web-dev web-test web-build dashboard-api-test dashboard-package

build:
	swift build

test:
	swift test

app:
	scripts/package-dev-app.sh

run:
	scripts/run-dev.sh

inspect:
	scripts/inspect-events.sh

diagnose:
	scripts/diagnose.sh

install-login:
	scripts/install-login-agent.sh

uninstall-login:
	scripts/uninstall-login-agent.sh

github-private:
	@if [ -z "$$REPO" ]; then echo "Usage: make github-private REPO=<repo-name>"; exit 1; fi
	scripts/create-private-github-repo.sh "$$REPO"

github-brain:
	@if [ -z "$$REPO" ]; then echo "Usage: make github-brain REPO=<repo-name>"; exit 1; fi
	scripts/create-private-github-brain-repo.sh "$$REPO"

web-dev:
	pnpm --dir apps/observer-web dev

web-test:
	pnpm --dir apps/observer-web test

web-build:
	pnpm --dir apps/observer-web build

dashboard-api-test:
	swift test --filter Dashboard

dashboard-package:
	scripts/package-dev-app.sh
