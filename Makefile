.PHONY: doctor format format-check install test

install:
	./install.sh

doctor:
	./scripts/doctor.sh

format:
	shfmt -w -i 2 -ci install.sh scripts/*.sh scripts/dojo tests/*.sh
	stylua lua scripts tests sfx

format-check:
	shfmt -d -i 2 -ci install.sh scripts/*.sh scripts/dojo tests/*.sh
	stylua --check lua scripts tests sfx

test:
	./tests/isolated.sh
	./tests/install.sh
	./tests/update.sh
