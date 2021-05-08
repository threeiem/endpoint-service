## Append tasks to the global tasks
test:: test-readme-toc

## doc related tasks
test-readme-toc: ## test if table of contents in README.md needs to be updated
	$(call INFO, "validating documentation TOC")
	@if grep -q '<!-- toc -->' ./README.md; then \
		bash -c "diff -c --ignore-blank-lines --strip-trailing-cr \
					<(cat ./README.md | docker run --rm -i quay.io/getpantheon/markdown-toc -; echo) \
					<(cat ./README.md | awk '/<!-- toc -->/{flag=1;next}/<!-- tocstop -->/{flag=0}flag' | sed '1d;\$$d')\
				" > /dev/null 2>&1 \
		|| { echo "ERROR: README.md table of contents needs updating. Run 'make update-readme-toc', commit and push changes to your branch."; exit 1; } \
	fi

update-readme-toc: ## update the Table of Contents in ./README.md (replaces <!-- toc --> tag)
	$(call INFO, "updating documentation TOC")
	@docker run --rm -v `pwd`:/src quay.io/getpantheon/markdown-toc -i /src/README.md > /dev/null

.PHONY:: test-readme-toc update-readme-toc
