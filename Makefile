.PHONY: build full minimal stage stage-minimal sync test

build full:
	LUNCH_TARGET=cm_biscuit-userdebug PATCH_PROFILE=full ./scripts/build.sh

minimal:
	LUNCH_TARGET=biscuit_minimal-userdebug PATCH_PROFILE=minimal CLEAN_BISCUIT_OUT=1 ./scripts/build.sh

stage:
	PATCH_PROFILE=full ./scripts/stage-tree.sh

stage-minimal:
	PATCH_PROFILE=minimal ./scripts/stage-tree.sh

sync:
	./scripts/sync.sh

test:
	bash tests/test-apply-patches.sh
	bash tests/test-compatibility.sh
	bash tests/test-minimal-product.sh
	bash tests/test-kernel-root-cmdline.sh
	bash tests/test-amonet2-bcb-slotselect.sh
	python3 tests/test-ota-slot-paths.py
	bash tests/test-led-countdown.sh
	bash tests/test-system-update.sh
