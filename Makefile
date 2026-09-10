# prunusdomestic.com: Jekyll site, built by GitHub Pages from main.
# Local builds run in Docker so no Ruby toolchain is needed on the host.

PORT ?= 8000
CLAUDE_PORT ?= 8765
JEKYLL := docker compose run --rm --service-ports jekyll

.DEFAULT_GOAL := help
.PHONY: help serve build claude_test kill_claude_test open bigimages check-links clean

help: ## show this list
	@grep -hE '^[a-z_-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:[^#]*## /|/' | column -t -s '|'

serve: ## run the Jekyll dev server with livereload at http://localhost:$(PORT)
	docker compose up

build: ## build the site once into _site/
	docker compose run --rm jekyll sh -lc 'bundle check || bundle install; bundle exec jekyll build'

claude_test: ## build, then serve _site on $(CLAUDE_PORT), separate from `serve` so Claude's own testing never kills your dev server
	docker compose run --rm jekyll sh -lc 'bundle check || bundle install; bundle exec jekyll build'
	uv run python3 -m http.server $(CLAUDE_PORT) --directory _site

kill_claude_test: ## stop the claude_test server only (never touches `serve` on $(PORT))
	@pkill -f "[h]ttp\.server $(CLAUDE_PORT)" && echo "stopped" || echo "nothing running on $(CLAUDE_PORT)"

open: ## open the local preview in the default browser
	xdg-open http://localhost:$(PORT) 2>/dev/null || open http://localhost:$(PORT)

bigimages: ## list images over 500KB (candidates for further scaling)
	@find assets -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -size +500k \
	  -exec du -h {} \; | sort -rh

check-links: ## build, then flag local links in _site that don't resolve to a file
	@$(MAKE) -s build
	@grep -rhoE '(href|src)="[^":][^"]*"' _site --include='*.html' \
	  | sed -E 's/^(href|src)="//; s/"$$//; s/#.*$$//' \
	  | grep -vE '^(https?:|mailto:|/?$$)' | sed -E 's#^/##' | sort -u \
	  | while read -r p; do [ -e "_site/$$p" ] || [ -e "_site/$${p%/}/index.html" ] || echo "missing: $$p"; done

clean: ## remove build output and OS/editor cruft
	rm -rf _site .jekyll-cache
	find . -name '.DS_Store' -delete
