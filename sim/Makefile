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

# Parts of this Makefile were adapted from pulp-platform: https://github.com/pulp-platform/pulpissimo

TESTBENCH ?= tb_cutie_top

.PHONY: build opt lib clean sim simc

mkfile_path := $(realpath $(dir $(abspath $(firstword $(MAKEFILE_LIST)))))

VOPT				?= vopt
VSIM				?= vsim
VLIB				?= vlib
VMAP				?= vmap

all: lib build opt

sim:
	$(VSIM) -64 -gui vopt_tb -L models_lib -L vip_lib \
		-suppress vsim-3009 -suppress vsim-8683 \
		+UVM_NO_RELNOTES -stats -t ps \
		-do "set StdArithNoWarnings 1; set NumericStdNoWarnings 1"

simc:
	$(VSIM) -64 -c vopt_tb -L models_lib -L vip_lib \
		-suppress vsim-3009 -suppress vsim-8683 \
		+UVM_NO_RELNOTES -stats -t ps \
		-do "set StdArithNoWarnings 1; set NumericStdNoWarnings 1" \
		-do "run -all" \
		-do "quit -code [examine -radix decimal sim:/tb_pulp/exit_status]"

ACC ?= +acc=npr

opt:
	$(VOPT) $(ACC) $(PA_FLAGS) -o vopt_tb $(TESTBENCH) -floatparameters+$(TESTBENCH) -work work $(SPEC)

build:
	$(VSIM) -c -do 'source compile.tcl; quit'

lib:
	@$(VLIB) work
	$(VMAP) work $(mkfile_path)/work

clean:
	@mkdir -p work
	@rm -r work 
	@touch modelsim.ini
	@rm modelsim.ini
	@touch transcript
	@rm transcript
