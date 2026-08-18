.PHONY: doctor format format-check install test

install:
	./install.sh

doctor:
	./scripts/doctor.sh

format:
	stylua lua tests

format-check:
	stylua --check lua tests

test:
	./tests/isolated.sh
