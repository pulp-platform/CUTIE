// ----------------------------------------------------------------------
//
// File: activationmemory_internal_wrapper.sv
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
// This module is used as a functional equivalent of a multibanked activation memory
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

// This module instantiates sets of full activation memories. Need at least two to have concurrent writes and reads.

module activationmemory_internal_wrapper
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned N_O = 512,
    parameter int unsigned K = 3,
    parameter int unsigned WEIGHT_STAGGER = 8,

    parameter int unsigned IMAGEWIDTH = 224,
    parameter int unsigned IMAGEHEIGHT = 224,
    parameter int unsigned TCN_WIDTH = 24,

    parameter int unsigned NUMBANKSETS = 3,
    parameter int unsigned NUMTCNBANKSET = 1,

    parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
    parameter int unsigned PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5, // Round up number of trits per word; cut excess
    parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,
    parameter int unsigned EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2,
    parameter int unsigned EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS,

    parameter int unsigned NUMDECODERSPERBANK = PHYSICALBITSPERWORD/8,

    parameter int unsigned NUMBANKS = K*WEIGHT_STAGGER, // Need K*NI trits per cycle, at the most
    parameter int unsigned TOTNUMTRITS = IMAGEWIDTH*IMAGEHEIGHT*N_I,
    parameter int unsigned TRITSPERBANK = (TOTNUMTRITS+NUMBANKS-1)/NUMBANKS,
    parameter int unsigned BANKDEPTH = (TRITSPERBANK+EFFECTIVETRITSPERWORD-1)/EFFECTIVETRITSPERWORD,
    parameter int unsigned LEFTSHIFTBITWIDTH = NUMBANKS > 1 ? $clog2(NUMBANKS) : 1,

    parameter int unsigned SPLITWIDTH = $clog2(WEIGHT_STAGGER)+1,

    parameter int unsigned BANKSETSBITWIDTH = NUMBANKSETS > 1 ? $clog2(NUMBANKSETS) : 1
    )
   (
    input logic                                         clk_i,
    input logic                                         rst_ni,

    // Input data

    input logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0] wdata_i,

    // Control signals

    input logic [0:NUMBANKS-1]                          read_enable_i,
    input logic [0:BANKSETSBITWIDTH-1]                  read_enable_bank_set_i,
    input logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]   read_addr_i, // Addresses for all memories

    input logic [0:NUMBANKS-1]                          write_enable_i, // Write enable for all memories
    input logic [0:BANKSETSBITWIDTH-1]                  write_enable_bank_set_i,
    input logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]   write_addr_i, // Addresses for all memories

    input logic [LEFTSHIFTBITWIDTH-1:0]                 left_shift_i,
    input logic [SPLITWIDTH-1:0]                        scatter_coefficient_i,
    input logic [$clog2(WEIGHT_STAGGER):0]              pixelwidth_i,
    input logic                                         tcn_actmem_set_shift_i,
    input logic [$clog2(TCN_WIDTH)-1:0]                 tcn_actmem_read_shift_i,
    input logic [$clog2(TCN_WIDTH)-1:0]                 tcn_actmem_write_shift_i,


    // Outputs

    output logic [0:NUMBANKS-1]                         ready_o,
    output logic [0:NUMBANKS-1]                         rw_collision_o,
    output logic [0:K-1][0:N_I-1][1:0]                  acts_o,
    output logic [PHYSICALBITSPERWORD-1:0]              encoded_acts_o
    );

   ///////////////////////////////// COMBINATORIAL SIGNALS /////////////////////////////////

   logic [0:NUMBANKSETS-1][PHYSICALBITSPERWORD-1:0]     encoded_acts_vec;

   logic [0:NUMBANKSETS-1][0:K-1][0:N_I-1][1:0]         acts;
   logic [0:(K*WEIGHT_STAGGER)-1][0:(N_I/WEIGHT_STAGGER)-1][1:0] acts_scatter_view;
   logic [0:(K*WEIGHT_STAGGER)-1][0:(N_I/WEIGHT_STAGGER)-1][1:0] acts_scattered;
   logic [0:NUMBANKSETS-1][0:NUMBANKS-1]                         ready;
   logic [0:NUMBANKSETS-1][0:NUMBANKS-1]                         rw_collision;
   logic [0:NUMBANKSETS-1][0:NUMBANKS-1]                         read_enable_vec;
   logic [0:NUMBANKSETS-1][0:NUMBANKS-1]                         write_enable_vec;
   logic [0:NUMBANKSETS-1][0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]  addr_vec;

   ///////////////////////////////// END COMBINATORIAL SIGNALS /////////////////////////////////

   ///////////////////////////////// SEQUENTIAL SIGNALS /////////////////////////////////

   // Save Readbank, leftshift and scattercoefficient, since memory has one cycle latency
   logic [0:BANKSETSBITWIDTH-1]                                  prev_read_bank;
   logic [LEFTSHIFTBITWIDTH-1:0]                                 left_shift_q;
   logic [SPLITWIDTH-1:0]                                        scatter_coefficient_q;

   ///////////////////////////////// END SEQUENTIAL SIGNALS /////////////////////////////////

   assign encoded_acts_o = encoded_acts_vec[prev_read_bank];

   always_comb begin

      acts_scatter_view = acts[prev_read_bank];

      acts_scattered = '0;
      // Scatter the activations to different pixels.
      for (int i=0;i<scatter_coefficient_q;i++)  begin
         for (int k=0;k<K;k++) begin
            acts_scattered[i+k*WEIGHT_STAGGER] = acts_scatter_view[i+k*scatter_coefficient_q];
         end
      end

      acts_o = acts_scattered;

      ready_o = ready[prev_read_bank];
      rw_collision_o = rw_collision[prev_read_bank];

      read_enable_vec = '0;
      write_enable_vec = '0;
      addr_vec = '0;

      write_enable_vec[write_enable_bank_set_i] = write_enable_i;
      read_enable_vec[read_enable_bank_set_i] = read_enable_i;

      addr_vec[write_enable_bank_set_i] = write_addr_i;

      if(read_enable_bank_set_i == write_enable_bank_set_i) begin
         for(int i=0;i<NUMBANKS;i++) begin
            if (write_enable_i[i] != 1 || read_enable_i[i] != 1) begin
               if(read_enable_i[i] == 1) begin
                  addr_vec[write_enable_bank_set_i][i] = read_addr_i[i];
               end
            end
         end
      end else begin
         addr_vec[read_enable_bank_set_i] = read_addr_i;
      end

   end


   for (genvar m = 0; m < NUMBANKSETS-NUMTCNBANKSET; m++) begin
      activationmemory
                   #(
                     .N_I(N_I),
                     .N_O(N_O),
                     .K(K),
                     .WEIGHT_STAGGER(WEIGHT_STAGGER),
                     .IMAGEWIDTH(IMAGEWIDTH),
                     .IMAGEHEIGHT(IMAGEHEIGHT)
                     )
      mem
                   (
                    .clk_i(clk_i),
                    .rst_ni(rst_ni),
                    .read_enable_i(read_enable_vec[m]),
                    .wdata_i(wdata_i),
                    .addr_i(addr_vec[m]),
                    .write_enable_i(write_enable_vec[m]),
                    .left_shift_i(left_shift_q),
                    .ready_o(ready[m]),
                    .rw_collision_o(rw_collision[m]),
                    .acts_o(acts[m]),
                    .encoded_acts_o(encoded_acts_vec[m])
                    );
   end // for (genvar m = 0; m < NUMBANKSETS-NUMTCNBANKSET; m++)

   tcn_activationmemory
     #(
       .N_I(N_I),
       .N_O(N_O),
       .K(K),
       .WEIGHT_STAGGER(WEIGHT_STAGGER),
       .IMAGEWIDTH(IMAGEWIDTH),
       .IMAGEHEIGHT(IMAGEHEIGHT),
       .TCN_WIDTH(TCN_WIDTH)
       )
   tcn_mem
     (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .read_enable_i(read_enable_vec[NUMBANKSETS-NUMTCNBANKSET]),
      .wdata_i(wdata_i),
      .addr_i(addr_vec[NUMBANKSETS-NUMTCNBANKSET]),
      .write_enable_i(write_enable_vec[NUMBANKSETS-NUMTCNBANKSET]),
      .left_shift_i(left_shift_q),
      .pixelwidth_i(pixelwidth_i),
      .tcn_actmem_set_shift_i(tcn_actmem_set_shift_i),
      .tcn_actmem_read_shift_i(tcn_actmem_read_shift_i),
      .tcn_actmem_write_shift_i(tcn_actmem_write_shift_i),
      .ready_o(ready[NUMBANKSETS-NUMTCNBANKSET]),
      .rw_collision_o(rw_collision[NUMBANKSETS-NUMTCNBANKSET]),
      .acts_o(acts[NUMBANKSETS-NUMTCNBANKSET]),
      .encoded_acts_o(encoded_acts_vec[NUMBANKSETS-NUMTCNBANKSET])
      );

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if (~rst_ni) begin
         prev_read_bank <= '0;
         left_shift_q <= '0;
         scatter_coefficient_q <= '0;
      end else begin
         prev_read_bank <= read_enable_bank_set_i;
         left_shift_q <= left_shift_i;
         scatter_coefficient_q <= scatter_coefficient_i;
      end
   end

endmodule
