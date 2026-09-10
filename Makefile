# prunusdomestic.com: Jekyll site, built by GitHub Pages from main.
# Local builds run in Docker so no Ruby toolchain is needed on the host.

PORT ?= 8000
CLAUDE_PORT ?= 8765
JEKYLL := docker compose run --rm --service-ports jekyll

# Search results render entities, so "&amp;" costs one character on screen, not
# five. Decode before measuring length. &amp; must come last, or "&amp;lt;"
# would decode twice and land on "<".
UNESCAPE := sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e 's/&amp;/\&/g'

.DEFAULT_GOAL := help
.PHONY: help serve build claude_test kill_claude_test open bigimages clean \
  check check-content check-images check-links check-ids check-popovers check-sitemap check-seo check-external check-orphans

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

# Each check is its own target so it can be run alone; `check` runs the lot.
# They all depend on `build`, and make runs a phony prerequisite only once per
# invocation, so `make check` still builds exactly one time. A failing check
# stops the rest - use `make -k check` to run every check regardless.
check: check-content check-images check-links check-ids check-popovers check-sitemap check-seo check-external check-orphans ## run every check below
	@echo; echo "all checks passed"

check-content: build ## every collection item declares images: and description:
	@echo "-- collection items: images: and description: --"; fail=0; \
	for f in _free_designs/*.html _products/*.html _classes/*.html _commissions/*.html; do \
	  [ -e "$$f" ] || continue; \
	  front=$$(awk 'NR==1{next} /^---$$/{exit} {print}' "$$f"); \
	  case "$$front" in *"images:"*) ;; \
	    *) echo "  ERROR $$f: no images: - its card renders an empty src"; fail=1;; esac; \
	  case "$$front" in *"description:"*) ;; \
	    *) echo "  ERROR $$f: no description: - falls back to the site-wide one"; fail=1;; esac; \
	done; exit $$fail

check-images: build ## no empty src, and every <img> carries alt text
	@echo "-- images: empty src, missing alt --"; fail=0; \
	out=$$(grep -rn 'src=""' _site --include='*.html'); \
	[ -n "$$out" ] && { echo "$$out" | sed 's/^/  ERROR empty src: /'; fail=1; }; \
	out=$$(grep -rno '<img[^>]*>' _site --include='*.html' | grep -v 'alt="[^"]'); \
	[ -n "$$out" ] && { echo "$$out" | sed 's/^/  ERROR no alt: /'; fail=1; }; \
	exit $$fail

check-links: build ## every internal link and image path resolves to a file
	@echo "-- internal links and image paths resolve --"; \
	out=$$(grep -rhoE '(href|src)="[^":][^"]*"' _site --include='*.html' \
	  | sed -E 's/^(href|src)="//; s/"$$//; s/#.*$$//' \
	  | grep -vE '^(https?:|mailto:|/?$$)' | sed -E 's#^/##' | sort -u \
	  | while read -r p; do [ -e "_site/$$p" ] || [ -e "_site/$${p%/}/index.html" ] \
	      || echo "  ERROR missing target: $$p"; done); \
	[ -z "$$out" ] || { echo "$$out"; exit 1; }

check-ids: build ## no duplicate element ids (they break popovertarget and anchors)
	@echo "-- duplicate ids --"; fail=0; \
	for f in $$(find _site -name '*.html'); do \
	  d=$$(grep -o 'id="[^"]*"' "$$f" | sort | uniq -d); \
	  [ -n "$$d" ] && { echo "  ERROR $${f#_site}: duplicate $$d"; fail=1; }; \
	done; exit $$fail

check-popovers: build ## every popovertarget points at an id that exists on the page
	@echo "-- popovertarget wiring --"; fail=0; \
	for f in $$(find _site -name '*.html'); do \
	  for t in $$(grep -o 'popovertarget="[^"]*"' "$$f" | sed 's/.*="//; s/"//' | sort -u); do \
	    grep -q "id=\"$$t\"" "$$f" || { echo "  ERROR $${f#_site}: popovertarget=$$t has no such id"; fail=1; }; \
	  done; \
	done; exit $$fail

check-sitemap: build ## every built page appears in sitemap.xml
	@echo "-- sitemap coverage --"; fail=0; \
	for f in $$(find _site -name '*.html'); do \
	  u=$$(echo "$${f#_site}" | sed 's#index\.html$$##'); \
	  grep -q "$$u</loc>" _site/sitemap.xml || { echo "  ERROR $$u not in sitemap"; fail=1; }; \
	done; exit $$fail

check-seo: build ## advisory: titles/descriptions longer than search results show
	@echo "-- titles over 60 chars --"; \
	grep -rho '<title>[^<]*</title>' _site --include='*.html' | sed 's/<[^>]*>//g' \
	  | $(UNESCAPE) | awk 'length > 60 {print "  " length " chars: " $$0}'; \
	echo "-- descriptions over 160 chars --"; \
	grep -rho 'name="description" content="[^"]*"' _site --include='*.html' \
	  | sed 's/.*content="//; s/"$$//' \
	  | $(UNESCAPE) | awk 'length > 160 {print "  " length " chars: " $$0}'

check-external: build ## advisory: external links that fail or redirect (needs network)
	@echo "-- external links (advisory: needs network, never fails the build) --"; \
	blocked=$$(mktemp); \
	grep -rhoE 'href="https?://[^"]+"' _site --include='*.html' \
	  | sed -E 's/^href="//; s/"$$//' | sort -u \
	  | while read -r u; do \
	      out=$$(curl -sSL -o /dev/null --max-time 20 --retry 1 \
	        -A 'Mozilla/5.0 (compatible; prunusdomestic-linkcheck/1.0)' \
	        -w '%{http_code} %{num_redirects} %{url_effective}' "$$u" 2>/dev/null); \
	      [ -n "$$out" ] || { echo "  ---  no response: $$u"; continue; }; \
	      code=$${out%% *}; rest=$${out#* }; hops=$${rest%% *}; final=$${rest#* }; \
	      case "$$code" in \
	        000) echo "  ---  no response: $$u";; \
	        403|429) h=$${u#*://}; echo "$${h%%/*}" >> "$$blocked";; \
	        4??|5??) echo "  $$code  BROKEN: $$u";; \
	        *) [ "$$hops" != "0" ] && { echo "  $$code  redirects: $$u"; echo "       -> $$final"; };; \
	      esac; \
	    done; \
	sort "$$blocked" | uniq -c | while read -r n h; do \
	  echo "  403  $$h blocked $$n link(s) - bot protection, not necessarily broken"; \
	done; \
	rm -f "$$blocked"; true

check-orphans: build ## advisory: unreferenced assets that have no _WxH resized copy
	@echo "-- unreferenced assets (skipping originals that have a _WxH copy) --"; \
	resized=$$(find assets -type f | tr ' ' '_' \
	  | sed -nE 's#^(.*)_[0-9]+x[0-9]+\.[^./]+$$#\1#p' | sort -u); \
	find assets -type f | sort | while read -r a; do \
	  grep -rqF "/$$a" _site css --include='*.html' --include='*.css' --include='*.xml' && continue; \
	  stem=$$(printf '%s' "$${a%.*}" | tr ' ' '_'); \
	  printf '%s\n' "$$resized" | grep -qFx "$$stem" || echo "  $$a"; \
	done

clean: ## remove build output and OS/editor cruft
	rm -rf _site .jekyll-cache
	find . -name '.DS_Store' -delete
