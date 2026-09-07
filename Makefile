# prunusdomestic.com — static site, deployed via GitHub Pages from main
# No build step: index.html/retail.html/pdx_local_retail.html are served as-is.

PORT ?= 8000

.DEFAULT_GOAL := help
.PHONY: help serve open bigimages check-links clean

help: ## show this list
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:[^#]*## /|/' | column -t -s '|'

serve: ## run a local preview server at http://localhost:$(PORT) (via uv)
	uv run python3 -m http.server $(PORT)

open: ## open the local preview in the default browser
	xdg-open http://localhost:$(PORT) 2>/dev/null || open http://localhost:$(PORT)

bigimages: ## list images over 500KB (candidates for further scaling)
	@find assets -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -size +500k \
	  -exec du -h {} \; | sort -rh

check-links: ## grep html for local links and flag ones that don't resolve to a file
	@grep -rhoE '(href|src)="[^":][^"]*"' *.html 2>/dev/null | sed -E 's/^(href|src)="//; s/"$$//; s/#.*$$//' \
	  | grep -vE '^(https?:|mailto:|/?$$)' | sed -E 's#^/##' | sort -u \
	  | while read -r p; do [ -e "$$p" ] || echo "missing: $$p"; done

clean: ## remove OS/editor cruft
	find . -name '.DS_Store' -delete
