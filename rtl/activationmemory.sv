// ----------------------------------------------------------------------
//
// File: activationmemory.sv
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
// This module is used as a functional equivalent single activation memory bank
// According to design specs, K*N_I trits have to be loaded per cycle.
// With the additional constraint of wordwidth, this leads to the number of banks needed, i.e.
// k*N_I/WEIGHT_STAGGER, where Wordwidth = N_I/WEIGHT_STAGGER

// Since we use 8-Bit/5-Trit Encoding, there might be some excessbits since the word might hold more than
// the necessary number of trits. (-> EXCESSBITS)

// We use a leftshift on the word level, just to stay configurable. It might be that we dont load the full K*NI words per cycle and instead zero stuff
// For the next cycle, the words won't be aligned properly, so we might have to shift.

// The module uses the weightmemory submodule, which contains a functional SRAM Bank and decoders.

// The interface supports full individual access of all banks at once.
// The scattering coefficient is used to distribute the loaded channels to neighboring pixels, in case less than the maximal input channels are loaded.

// Access priority is given to write requests, read requests are lost if there is a collision.

module activationmemory
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned N_O = 512,
    parameter int unsigned K = 3,
    parameter int unsigned WEIGHT_STAGGER = 8,

    parameter int unsigned IMAGEWIDTH = 224,
    parameter int unsigned IMAGEHEIGHT = 224,

    parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
    parameter int unsigned PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5, // Round up number of trits per word; cut excess
    parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,
    parameter int unsigned EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2,
    parameter int unsigned EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS,
    parameter int unsigned NUMDECODERSPERBANK = PHYSICALBITSPERWORD/8,

    parameter int unsigned NUMBANKS = K*WEIGHT_STAGGER, // Need K*NI trits per cycle
    parameter int unsigned TOTNUMTRITS = IMAGEWIDTH*IMAGEHEIGHT*N_I,
    parameter int unsigned TRITSPERBANK = (TOTNUMTRITS+NUMBANKS-1)/NUMBANKS,
    parameter int unsigned BANKDEPTH = (TRITSPERBANK+EFFECTIVETRITSPERWORD-1)/EFFECTIVETRITSPERWORD,
    parameter int unsigned LEFTSHIFTBITWIDTH = NUMBANKS > 1 ? $clog2(NUMBANKS) : 1
    )
   (
    input logic                                         clk_i,
    input logic                                         rst_ni,
    input logic [0:NUMBANKS-1]                          read_enable_i,

    input logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0] wdata_i,
    input logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]   addr_i, // Addresses for all memories
    input logic [0:NUMBANKS-1]                          write_enable_i, // Write enable for all memories

    input logic [LEFTSHIFTBITWIDTH-1:0]                 left_shift_i,

    output logic [0:NUMBANKS-1]                         ready_o,
    output logic [0:NUMBANKS-1]                         rw_collision_o,
    output logic [0:K-1][0:N_I-1][1:0]                  acts_o,
    output logic [PHYSICALBITSPERWORD-1:0]              encoded_acts_o
    );

   logic [0:NUMBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0] acts_vec;
   logic [0:NUMBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0] zeroed_acts_vec;
   logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0]        encoded_acts_vec;
   logic [0:NUMBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0] output_vec;

   always_comb begin
      encoded_acts_o = encoded_acts_vec[left_shift_i];
   end

   // Zero all outputs that are NOT valid in this cycle.
   always_comb begin
      for (int i=0;i<NUMBANKS;i++) begin
         if (ready_o[i] == '0) begin
            zeroed_acts_vec[i] = '0;
         end else begin
            zeroed_acts_vec[i] = acts_vec[i];
         end
      end
   end

   // Left shift all trits cyclically by EFFECTIVETRITSPERWORD*left_shift_i
   always_comb begin
      for(int i=0;i<NUMBANKS;i++) begin
         output_vec[i] = zeroed_acts_vec[(i+left_shift_i)%NUMBANKS];
      end
   end

   assign acts_o = {>>{output_vec}};

   genvar                                          m;
   generate
      for (m=0;m<NUMBANKS;m++) begin
         activationmemorybank
             #(
               .N_I(N_I),
               .K(K),
               .WEIGHT_STAGGER(WEIGHT_STAGGER),
               .BANKDEPTH(BANKDEPTH)
               )
         mem
             (
              .clk_i(clk_i),
              .rst_ni(rst_ni),
              .read_enable_i(read_enable_i[m]),
              .wdata_i(wdata_i[m]),
              .addr_i(addr_i[m]),
              .write_enable_i(write_enable_i[m]),
              .ready_o(ready_o[m]),
              .rw_collision_o(rw_collision_o[m]),
              .weights_o(acts_vec[m]),
              .weights_encoded_o(encoded_acts_vec[m])
              );
      end
   endgenerate

endmodule
