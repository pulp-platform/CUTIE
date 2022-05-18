// ----------------------------------------------------------------------
//
// File: weightmemory_external_wrapper.sv
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
// This module instantiates a weightmemory_internal_wrapper and adds access source arbitration.
// Priority is as follows: External Access > Internal Access
// Colliding requests are not saved, the highest priority request is run

module weightmemory_external_wrapper
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

    parameter int unsigned NUMDECODERS = PHYSICALBITSPERWORD/8,

    parameter int unsigned FULLADDRESSBITWIDTH = $clog2(BANKDEPTH)
    )
   (
    input logic                                   external_we_i,
    input logic                                   external_req_i,
    input logic [FULLADDRESSBITWIDTH-1:0]         external_addr_i,
    input logic [PHYSICALBITSPERWORD-1:0]         external_wdata_i,

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


    output logic                                  valid_o,
    output logic                                  rw_collision_o,
    output logic [0:EFFECTIVETRITSPERWORD-1][1:0] weights_o,

    output logic [PHYSICALBITSPERWORD-1:0]        external_weights_o,
    output logic                                  external_valid_o
    );

   ///////////////////////////////// COMBINATORIAL SIGNALS /////////////////////////////////

   logic [PHYSICALBITSPERWORD-1:0]                wdata;
   logic                                          read_enable;
   logic [$clog2(BANKDEPTH)-1:0]                  read_addr;
   logic                                          write_enable;
   logic [$clog2(BANKDEPTH)-1:0]                  write_addr;
   logic [PHYSICALBITSPERWORD-1:0]                weights_encoded;

   logic                                          valid;
   logic                                          rw_collision;
   logic [0:EFFECTIVETRITSPERWORD-1][1:0]         weights;

   ///////////////////////////////// END COMBINATORIAL SIGNALS /////////////////////////////////

   ///////////////////////////////// SEQUENTIAL SIGNALS /////////////////////////////////

   logic                                          command_source, command_source_q;
   logic                                          prev_external_we;

   ///////////////////////////////// END SEQUENTIAL SIGNALS /////////////////////////////////

   always_comb begin

      read_enable = '0;
      write_enable = '0;
      read_addr = '0;
      write_addr = '0;
      wdata = '0;

      // Access source arbitration
      if(external_req_i == 1) begin
         command_source = 1;
         read_enable = ~external_we_i;
         write_enable = external_we_i;
         read_addr = external_addr_i;
         write_addr = external_addr_i;
         wdata = external_wdata_i;
      end else begin // if (external_req_i == 1)
         command_source = 0;
         read_enable = read_enable_i;
         write_enable = write_enable_i;
         read_addr = read_addr_i;
         write_addr = write_addr_i;
         wdata = wdata_i;
      end
   end // always_comb

   always_comb begin
      external_weights_o = weights_encoded;
      if(command_source_q == 1) begin
         external_valid_o = ~prev_external_we;
         valid_o = '0;
         rw_collision_o = '1;
         weights_o = '0;
      end else begin
         external_valid_o = 0;
         valid_o = valid;
         rw_collision_o = rw_collision;
         weights_o = weights;
      end
   end

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if (~rst_ni) begin
         command_source_q <= '0;
         prev_external_we <= '0;
      end else begin
         command_source_q <= command_source;
         prev_external_we <= external_we_i;
      end
   end

   weightmemory_internal_wrapper   #(
                                     .N_I(N_I),
                                     .K(K),
                                     .WEIGHT_STAGGER(WEIGHT_STAGGER),
                                     .BANKDEPTH(BANKDEPTH)
                                     ) weightmem (
                                                  .clk_i(clk_i),
                                                  .rst_ni(rst_ni),
                                                  .read_enable_i(read_enable),
                                                  .wdata_i(wdata),
                                                  .read_addr_i(read_addr),
                                                  .write_addr_i(write_addr),
                                                  .write_enable_i(write_enable),
                                                  .ready_o(valid),
                                                  .rw_collision_o(rw_collision),
                                                  .weights_o(weights),
                                                  .weights_encoded_o(weights_encoded)
                                                  );

endmodule
