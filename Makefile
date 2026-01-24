.PHONY: all test check lint

all: check test

test:
	./test-notestash.sh

check lint:
	shellcheck git-notestash test-notestash.sh
