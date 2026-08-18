.PHONY: doctor format format-check install test

install:
	./install.sh

doctor:
	./scripts/doctor.sh

format:
	shfmt -w -i 2 -ci install.sh scripts/*.sh tests/*.sh
	stylua lua scripts tests

format-check:
	shfmt -d -i 2 -ci install.sh scripts/*.sh tests/*.sh
	stylua --check lua scripts tests

test:
	./tests/isolated.sh
	./tests/install.sh
