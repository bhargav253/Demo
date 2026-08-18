ROUTER_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BOOKSIM := $(ROUTER_DIR)/booksim2/src/booksim
CONFIG := $(ROUTER_DIR)/configs/single_router_uniform.cfg
RESULT_DIR := $(ROUTER_DIR)/results

.PHONY: setup run run-voq run-trace run-directed run-full-load run-credit-sweep run-credit-sweep-t3 run-credit-sweep-t4-p5 run-bypass-sweep run-full-load-matrix run-banked-sweep run-fixed-depth-sweep run-fixed-exact-credit-sweep run-vc-sharing-sweep run-read-latency-sweep run-noc16-smoke run-noc16-initial run-noc16-phase3 run-noc16-grant-comparison run-noc12-grant-comparison run-noc16c-grant-comparison test test-bank test-vc test-noc-prereqs test-noc16 test-noc12 test-noc16c clean-results

setup:
	$(ROUTER_DIR)/scripts/bootstrap.sh

run: $(BOOKSIM)
	mkdir -p $(RESULT_DIR)
	$(BOOKSIM) $(CONFIG) | tee $(RESULT_DIR)/single_router_uniform.log

run-voq: $(BOOKSIM)
	mkdir -p $(RESULT_DIR)
	$(BOOKSIM) $(ROUTER_DIR)/configs/lane_voq_flop_4p16s.cfg | \
		tee $(RESULT_DIR)/lane_voq_flop_4p16s.log

run-trace: $(BOOKSIM)
	mkdir -p $(RESULT_DIR)
	$(BOOKSIM) $(ROUTER_DIR)/configs/lane_voq_trace_2lane.cfg | \
		tee $(RESULT_DIR)/lane_voq_trace_2lane.log

run-directed: $(BOOKSIM)
	mkdir -p $(RESULT_DIR)
	@for test in \
		t1_one_port_all_lanes \
		t2_all_ports_one_lane_hotspot \
		t3_all_ports_all_lanes_hotspot \
		t4_all_ports_all_lanes_balanced; do \
		$(BOOKSIM) $(ROUTER_DIR)/configs/$$test.cfg > $(RESULT_DIR)/$$test.log; \
		grep -q "Overall Traffic Statistics" $(RESULT_DIR)/$$test.log || exit 1; \
		echo "completed $$test"; \
		done

run-full-load: $(BOOKSIM)
	mkdir -p $(RESULT_DIR)
	@for test in \
		t1_one_port_all_lanes \
		t2_all_ports_one_lane_hotspot \
		t3_all_ports_all_lanes_hotspot \
		t4_all_ports_all_lanes_balanced; do \
		$(BOOKSIM) $(ROUTER_DIR)/configs/$$test.cfg \
			injection_rate=1.0 sim_type=throughput voq_ideal_output=1 \
			voq_trace_file=$(RESULT_DIR)/$${test}_full.csv \
			> $(RESULT_DIR)/$${test}_full.log; \
		grep -q "Overall Traffic Statistics" $(RESULT_DIR)/$${test}_full.log || exit 1; \
		echo "completed $${test}_full"; \
	done

run-credit-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_credit_sweep.sh t4

run-credit-sweep-t3: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_credit_sweep.sh t3

run-credit-sweep-t4-p5: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_credit_sweep.sh t4_p5

run-bypass-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_bypass_sweep.sh

run-full-load-matrix: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_full_load_matrix.sh

run-banked-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_banked_sweep.sh

run-fixed-depth-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_fixed_depth_sweep.sh

run-fixed-exact-credit-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_fixed_exact_credit_sweep.sh

run-vc-sharing-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_vc_sharing_sweep.sh

run-read-latency-sweep: $(BOOKSIM)
	$(ROUTER_DIR)/scripts/run_read_latency_sweep.sh

test-vc:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/tests/run_vc_sharing_tests.sh

test-noc-prereqs:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(CXX) -std=c++11 -I$(ROUTER_DIR)/booksim2/src \
		$(ROUTER_DIR)/tests/noc16_map_test.cpp \
		$(ROUTER_DIR)/booksim2/src/networks/noc16_map.cpp \
		-o /tmp/noc16_map_test
	/tmp/noc16_map_test
	@mkdir -p $(RESULT_DIR)
	@set +e; $(BOOKSIM) $(ROUTER_DIR)/configs/l3_router_smoke.cfg > $(RESULT_DIR)/l3_router_smoke.log; status=$$?; \
	  set -e; test $$status -eq 0 -o $$status -eq 255
	@grep -q 'Accepted packet rate average' $(RESULT_DIR)/l3_router_smoke.log
	@grep -q 'Hops average = 1' $(RESULT_DIR)/l3_router_smoke.log
	@grep -q 'storage=sram_fixed policy=fixed' $(RESULT_DIR)/l3_router_smoke.log
	@echo 'Heterogeneous one-lane L3 router prerequisite passed.'

run-noc16-smoke:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	@mkdir -p $(RESULT_DIR)
	@set +e; $(BOOKSIM) $(ROUTER_DIR)/configs/noc16_smoke.cfg > $(RESULT_DIR)/noc16_smoke.log; status=$$?; \
	  set -e; test $$status -eq 0 -o $$status -eq 255
	@grep 'Overall Traffic Statistics' $(RESULT_DIR)/noc16_smoke.log
	@grep 'Network latency average = 10 ' $(RESULT_DIR)/noc16_smoke.log
	@grep 'Hops average = 4 ' $(RESULT_DIR)/noc16_smoke.log
	@test -s $(RESULT_DIR)/noc16_smoke_telemetry.csv
	@grep -q ',router,0,L1_00,' $(RESULT_DIR)/noc16_smoke_telemetry.csv
	@grep -q ',shim,96,SHIM_00_00,' $(RESULT_DIR)/noc16_smoke_telemetry.csv
	@grep -q ',endpoint,0,PE_00_00,' $(RESULT_DIR)/noc16_smoke_telemetry.csv
	@grep -q ',endpoint,320,LLCH_00,' $(RESULT_DIR)/noc16_smoke_telemetry.csv

run-noc16-initial:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/scripts/run_noc16_initial.sh

run-noc16-phase3:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/scripts/run_noc16_phase3_sweep.sh

run-noc16-grant-comparison:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/scripts/run_noc16_grant_comparison.sh

run-noc12-grant-comparison:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/scripts/run_noc12_grant_comparison.sh
	$(ROUTER_DIR)/scripts/compare_noc12_noc16.py

run-noc16c-grant-comparison:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/scripts/run_noc16c_grant_comparison.sh

test-noc16: test-noc-prereqs run-noc16-smoke
	$(ROUTER_DIR)/tests/run_noc16_route_tests.sh
	$(ROUTER_DIR)/tests/run_noc16_shim_tests.sh
	$(ROUTER_DIR)/tests/run_noc16_port_telemetry_tests.sh
	@echo 'noc16 graph, heterogeneous routers, shim path, delivery, and drain passed.'

test-noc12:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/tests/run_noc12_tests.sh

test-noc16c:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/tests/run_noc16c_tests.sh

test:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/tests/run_router_tests.sh

test-bank:
	$(MAKE) -C $(ROUTER_DIR)/booksim2/src -j4
	$(ROUTER_DIR)/tests/run_bank_tests.sh

$(BOOKSIM):
	@echo "BookSim has not been built. Run: make setup" >&2
	@exit 1

clean-results:
	rm -f $(RESULT_DIR)/single_router_uniform.log
