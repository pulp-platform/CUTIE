# ----------------------------------------------------------------------
#
# File: Makefile
#
# Created: 05.05.2022        
# 
# Copyright (C) 2022, ETH Zurich and University of Bologna.
#
# Author: Moritz Scherer, ETH Zurich
#
# ----------------------------------------------------------------------
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the License); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an AS IS BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SIM_BUILD_DIR = sim
export ROOT = $(pwd)

.PHONY: checkout scripts clean sim gen

download:
ifeq (,$(wildcard ./bender))
	@echo "Downloading Bender..."
	@curl --proto '=https' --tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- 0.25.2
endif

clean:
	@rm -rf ./sim/work
	@rm -f ./synth/scripts/analyze_top.tcl
	@rm -f ./sim/compile.tcl
	@rm -f ./stimuli/compute_output_*
	@rm -f ./stimuli/activations.txt
	@rm -f ./stimuli/activations_intf.txt
	@rm -f ./stimuli/thresholds.txt
	@rm -f ./stimuli/thresholds_intf.txt
	@rm -f ./stimuli/responses.txt
	@rm -f ./stimuli/responses_intf.txt
	@rm -f ./stimuli/weights.txt
	@rm -f ./stimuli/weights_intf.txt
	@rm -f ./stimuli/layer_params.txt
	@rm -f ./stimuli/layer_params_intf.txt
	@rm -f ./stimuli/test_params.txt
	@rm -f ./stimuli/tcn_sequence.txt
	@make -C ./sim clean

checkout: download
	@./bender update
	@touch Bender.lock

scripts: download scripts-bender-vsim

scripts-bender-vsim: | Bender.lock
	@echo 'set ROOT [file normalize [file dirname [info script]]/..]' > $(SIM_BUILD_DIR)/compile.tcl
	@./bender script vsim \
		--vlog-arg="$(VLOG_ARGS)" --vcom-arg="" \
		 -t simulation -t test  \
		| grep -v "set ROOT" >> $(SIM_BUILD_DIR)/compile.tcl

$(SIM_BUILD_DIR)/compile.tcl: | Bender.lock
	@echo 'set ROOT [file normalize [file dirname [info script]]/..]' > $(SIM_BUILD_DIR)/compile.tcl
	@./bender script vsim \
		--vlog-arg="$(VLOG_ARGS)" --vcom-arg="" \
	 -t rtl -t test  \
	| grep -v "set ROOT" >> $(SIM_BUILD_DIR)/compile.tcl

build-sim: $(SIM_BUILD_DIR)/compile.tcl
	@test -f Bender.lock || { echo "ERROR: Bender.lock file does not exist. Did you run make checkout in bender mode?"; exit 1; }
	@test -f $(SIM_BUILD_DIR)/compile.tcl || { echo "ERROR: sim/compile.tcl file does not exist. Did you run make scripts in bender mode?"; exit 1; }
	cd sim && $(MAKE) BENDER=bender all

sim: scripts build-sim
	make -C ./sim sim

gen:
	@cd stimuli && python ./compute_tcn.py
