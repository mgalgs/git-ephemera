.PHONY: all test check lint

all: check test

test:
	./test-ephemera.sh

check lint:
	shellcheck git-ephemera test-ephemera.sh
