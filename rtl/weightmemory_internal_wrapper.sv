// ----------------------------------------------------------------------
//
// File: weightmemory_internal_wrapper.sv
//
// Created: 06.05.2022
//
// Copyright (C) 2022, ETH Zurich and University of Bologna.
//
// Author: Moritz Scherer, ETH Zurich
//
// SPDX-License-Identifier: SHL-0.51
//
// Copyright and related rights are licensed under the Solderpad Hardware License,
// Version 0.51 (the "License"); you may not use this file except in compliance with
// the License. You may obtain a copy of the License at http://solderpad.org/licenses/SHL-0.51.
// Unless required by applicable law or agreed to in writing, software, hardware and materials
// distributed under this License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and limitations under the License.
//
// ----------------------------------------------------------------------
// The weightmemory_internal_wrapper moduke uses one weightmemory module and adds address arbitration.
// Write accesses take priority.

module weightmemory_internal_wrapper
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned K = 3,
    parameter int unsigned WEIGHT_STAGGER = 8,
    parameter int unsigned BANKDEPTH = 1024,

    parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
    parameter int unsigned PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5, // Round up number of trits per word; cut excess
    parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,
    parameter int unsigned EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2,
    parameter int unsigned EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS,

    parameter int unsigned NUMDECODERS = PHYSICALBITSPERWORD/8
    )
   (
    // Data in
    input logic [PHYSICALBITSPERWORD-1:0]         wdata_i, // Data for up to all OCUs at once

    input logic                                   clk_i,
    input logic                                   rst_ni,

    // Memory access logic
    input logic                                   read_enable_i,
    input logic                                   write_enable_i, // Write enable for all memories

    // Addresses
    input logic [$clog2(BANKDEPTH)-1:0]           read_addr_i, // Addresses for all memories
    input logic [$clog2(BANKDEPTH)-1:0]           write_addr_i, // Addresses for all memories


    output logic                                  ready_o, // Actually valid, not ready. Misnomer
    output logic                                  rw_collision_o,
    output logic [0:EFFECTIVETRITSPERWORD-1][1:0] weights_o,

    output logic [PHYSICALBITSPERWORD-1:0]        weights_encoded_o
    );

   logic [$clog2(BANKDEPTH)-1:0]                  addr;
   logic [PHYSICALBITSPERWORD-1:0]                weights_encoded;

   assign weights_encoded_o = weights_encoded;

   always_comb begin

      if(write_enable_i == 1) begin
         addr = write_addr_i;
      end else begin
         addr = read_addr_i;
      end
   end

   weightmemory
     #(
       .N_I(N_I),
       .K(K),
       .WEIGHT_STAGGER(WEIGHT_STAGGER),
       .BANKDEPTH(BANKDEPTH)
       ) mem_bank
       (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .read_enable_i(read_enable_i),
        .write_enable_i(write_enable_i),
        .addr_i(addr),
        .wdata_i(wdata_i),
        .ready_o(ready_o),
        .rw_collision_o(rw_collision_o),
        .weights_o(weights_o),
        .weights_encoded_o(weights_encoded)
        );

endmodule
