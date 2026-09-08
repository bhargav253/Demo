REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PYTHON ?= python3
FUSESOC := $(REPO_ROOT)/tools/bin/fusesoc
comma := ,

.PHONY: doctor bootstrap script cores lint sim sim-regress coverage clean

doctor:
	$(PYTHON) $(REPO_ROOT)/tools/env/doctor.py

bootstrap:
	$(PYTHON) $(REPO_ROOT)/tools/env/bootstrap.py

# Compatibility alias for the old setup entry point.
script: bootstrap

cores:
	$(FUSESOC) core list

lint:
	$(PYTHON) $(REPO_ROOT)/tools/build/run_target.py lint --core "$(CORE)" --target "$(or $(TARGET),lint)"

sim:
	$(PYTHON) $(REPO_ROOT)/tools/build/run_target.py sim --core "$(CORE)" --target "$(or $(TARGET),sim)" --test "$(or $(TEST),smoke)" --seed "$(or $(SEED),1)" --cycles "$(or $(CYCLES),200)" $(if $(filter 1 true yes,$(REBUILD)),--rebuild,)

sim-regress:
	$(PYTHON) $(REPO_ROOT)/tools/build/run_regression.py --core "$(CORE)" --target "$(or $(TARGET),sim)" --test "$(or $(TEST),random)" --seed-start "$(or $(SEED_START),1)" --seed-count "$(or $(SEED_COUNT),1)" --jobs "$(or $(JOBS),1)" --cycles "$(or $(CYCLES),200)" $(if $(filter 1 true yes,$(REBUILD)),--rebuild,)

coverage:
	$(PYTHON) $(REPO_ROOT)/tools/build/run_coverage.py --core "$(CORE)" --target "$(or $(TARGET),coverage)" --tests "$(or $(COVERAGE_TESTS),smoke$(comma)directed$(comma)random)" --seed-start "$(or $(SEED_START),1)" --seed-count "$(or $(SEED_COUNT),1)" --jobs "$(or $(JOBS),1)" --cycles "$(or $(CYCLES),200)" $(if $(MERGE_FROM),--merge-from "$(MERGE_FROM)",) $(if $(filter 1 true yes,$(REBUILD)),--rebuild,)

clean:
	$(PYTHON) $(REPO_ROOT)/tools/env/clean.py

# Temporary Stage 1 entry points; Stage 2 owns the replacement CLI.
.PHONY: formal check-ip
formal:
	$(PYTHON) $(REPO_ROOT)/tools/build/run_target.py formal --core "$(CORE)" --target "$(or $(TARGET),formal)"

check-ip:
	$(PYTHON) $(REPO_ROOT)/tools/build/check_ip.py --core "$(CORE)" --seed-count "$(or $(SEED_COUNT),100)" --jobs "$(or $(JOBS),8)" --cycles "$(or $(CYCLES),200)"
