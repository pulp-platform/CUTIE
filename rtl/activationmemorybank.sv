// ----------------------------------------------------------------------
//
// File: activationmemorybank.sv
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
// The weightmemory module is an SRAM bank that saves encoded trits, according to
// https://hal.archives-ouvertes.fr/hal-02103214/document
// It also features decoders, that are hardwired to the output.

module activationmemorybank
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
    input logic                                   clk_i,
    input logic                                   rst_ni,
    input logic                                   read_enable_i,

    input logic [PHYSICALBITSPERWORD-1:0]         wdata_i, // Data for up to all OCUs at once
    input logic [$clog2(BANKDEPTH)-1:0]           addr_i, // Addresses for all memories
    input logic                                   write_enable_i, // Write enable for all memories

    output logic                                  ready_o,
    output logic                                  rw_collision_o,
    output logic [0:EFFECTIVETRITSPERWORD-1][1:0] weights_o,
    output logic [PHYSICALBITSPERWORD-1:0]        weights_encoded_o
    );

   ///////////////////////////////// COMBINATORIAL SIGNALS /////////////////////////////////

   logic [PHYSICALBITSPERWORD-1:0]                weights_encoded;
   logic [PHYSICALBITSPERWORD-1:0]                weights_encoded_pseudo;
   logic [NUMDECODERS-1:0][7:0]                   weights_encoded_decoder_view;
   logic [NUMDECODERS-1:0][4:0][1:0]              weights_decoded;
   logic [PHYSICALTRITSPERWORD-1:0][1:0]          weights_decoded_physical_view;
   logic [EFFECTIVETRITSPERWORD-1:0][1:0]         weights_decoded_effective_view;

   logic                                          req, write_enable;

   logic [$clog2(BANKDEPTH)-1:0]                  addr;

   ///////////////////////////////// END COMBINATORIAL SIGNALS /////////////////////////////////

   ///////////////////////////////// SEQUENTIAL SIGNALS /////////////////////////////////

   logic                                          collision_d, collision_q;
   logic                                          prev_ready;
   logic [PHYSICALBITSPERWORD-1:0]                be;

   ///////////////////////////////// END SEQUENTIAL SIGNALS /////////////////////////////////

   assign be = '1;
   assign weights_encoded_o = weights_encoded;
   assign rw_collision_o = collision_q;
   assign addr = addr_i;
   assign ready = ~collision_q & read_enable_i;
   assign ready_o = prev_ready;
   assign weights_o = weights_decoded_effective_view;

   assign weights_decoded_physical_view = {<<2{weights_decoded}};

   always_comb begin
      weights_encoded_decoder_view = {>>{weights_encoded}};
      for (int trits = 0; trits<EFFECTIVETRITSPERWORD; trits++) begin
         weights_decoded_effective_view[trits] = weights_decoded_physical_view[EFFECTIVETRITSPERWORD-1-trits];
      end
   end

   always_comb begin
      if(write_enable_i && read_enable_i) begin
         collision_d = '1;
      end else begin
         collision_d = '0;
      end

   end

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         collision_q <= '0;
         prev_ready <= '0;
      end else begin
         prev_ready <= ready;
         collision_q <= collision_d;
      end
   end

   always_comb begin
      write_enable = write_enable_i; // Write takes priority. Don't read if collision
      req = write_enable || read_enable_i;
   end // always_comb

   sram_actmem
     ram_bank
       (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_i(req),
        .we_i(write_enable),
        .addr_i(addr),
        .wdata_i(wdata_i),
        .be_i(be), // Always change all bits
        .rdata_o(weights_encoded)
        );

   genvar n;
   generate
      for (n=0; n<NUMDECODERS; n++) begin : decoders
         decoder dec (
                      .decoder_i(weights_encoded_decoder_view[n]),
                      .decoder_o(weights_decoded[n])
                      );
      end
   endgenerate

endmodule
