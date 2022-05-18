// ----------------------------------------------------------------------
//
// File: tcn_activationmemory.sv
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

module tcn_activationmemory
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned N_O = 512,
    parameter int unsigned K = 3,
    parameter int unsigned WEIGHT_STAGGER = 8,

    parameter int unsigned IMAGEWIDTH = 224,
    parameter int unsigned IMAGEHEIGHT = 224,
    parameter int unsigned TCN_WIDTH = 24,

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
    input logic [$clog2(WEIGHT_STAGGER):0]              pixelwidth_i,
    input logic                                         tcn_actmem_set_shift_i,
    input logic [$clog2(TCN_WIDTH)-1:0]                 tcn_actmem_read_shift_i,
    input logic [$clog2(TCN_WIDTH)-1:0]                 tcn_actmem_write_shift_i,


    output logic [0:NUMBANKS-1]                         ready_o,
    output logic [0:NUMBANKS-1]                         rw_collision_o,
    output logic [0:K-1][0:N_I-1][1:0]                  acts_o,
    output logic [PHYSICALBITSPERWORD-1:0]              encoded_acts_o
    );

   logic [0:NUMBANKS-1]                                 req;
   logic [0:NUMBANKS-1]                                 ready;
   logic [0:NUMBANKS-1]                                 read_enable_q;
   logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]          addr_q;
   logic [LEFTSHIFTBITWIDTH-1:0]                        left_shift_q;

   logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0]        acts_encoded;
   logic [0:NUMBANKS-1][0:NUMDECODERSPERBANK-1][7:0]    acts_encoded_decoder_view;
   logic [0:NUMBANKS-1][0:NUMDECODERSPERBANK-1][4:0][1:0] acts_decoded;
   logic [0:NUMBANKS-1][0:PHYSICALTRITSPERWORD-1][1:0]    acts_decoded_physical_view;
   logic [0:NUMBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0]   acts_decoded_effective_view;
   logic [0:NUMBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0]   zeroed_acts_vec;
   logic [0:NUMBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0]   output_vec;

   logic [0:WEIGHT_STAGGER-1][PHYSICALBITSPERWORD-1:0]    shiftmem_data_in;
   logic [0:WEIGHT_STAGGER-1]                             shiftmem_save_enable;
   logic [0:TCN_WIDTH-1][PHYSICALBITSPERWORD-1:0]         shiftmem_data_out;

   logic [$clog2(WEIGHT_STAGGER):0]                       pixelwidth;

   always_comb begin : write
      shiftmem_save_enable = '0;
      shiftmem_data_in = '0;

      for(int i = 0, int j = 0; i < NUMBANKS; i++) begin
         if(write_enable_i[i]) begin
            shiftmem_save_enable[j] = write_enable_i[i];
            shiftmem_data_in[j] = wdata_i[i];
            j++;
         end
      end
   end // block: write

   always_comb begin : read

      for(int i = 0; i < NUMBANKS; i++) begin
         acts_encoded[i] = {10{8'b11111001}};
      end
      encoded_acts_o = '0;

      for(int i = 0; i < NUMBANKS; i++) begin
         if(read_enable_q[i]) begin
            acts_encoded[i] = shiftmem_data_out[addr_q[i]*NUMBANKS+i];
         end
      end

      // Reshape encoded activations
      // (NUMBANKS, PHYSICALBITSPERWORD) -> (NUMBANKS, NUMDECODERSPERBANK, 8)
      acts_encoded_decoder_view = acts_encoded;

      // Reshape decoder output
      // (NUMBANKS, NUMDECODERSPERBANK, 5*2) -> (NUMBANKS, PHYSICALTRITSPERWORD, 2)
      acts_decoded_physical_view = acts_decoded;

      // Remove excess trits
      for (int i = 0; i < NUMBANKS; i++) begin
         acts_decoded_effective_view[i] = acts_decoded_physical_view[i][0:EFFECTIVETRITSPERWORD-1];
      end

      // Left shift all trits cyclically by EFFECTIVETRITSPERWORD*left_shift_i
      for(int i=0;i<NUMBANKS;i++) begin
         output_vec[i] = acts_decoded_effective_view[(i+left_shift_i)%NUMBANKS];
      end

      // actual outputs
      acts_o = output_vec;
      encoded_acts_o = (|read_enable_q)? acts_encoded[left_shift_q] : '0;
      ready_o = ready;
   end

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         rw_collision_o <= '0;
         ready <= '0;
         read_enable_q <= '0;
         addr_q <= '0;
         left_shift_q <= '0;
         pixelwidth <= '0;
      end else begin
         rw_collision_o <= read_enable_i & write_enable_i;
         ready <= ~rw_collision_o & read_enable_i;
         read_enable_q <= read_enable_i;
         addr_q <= addr_i;
         left_shift_q <= left_shift_i;
         pixelwidth <= (pixelwidth_i != 0)? pixelwidth_i : pixelwidth;
      end
   end

   for (genvar m = 0; m < NUMBANKS; m++) begin : decoder_bank
      for (genvar n = 0; n < NUMDECODERSPERBANK; n++) begin : decoder_word
         decoder dec (
                      .decoder_i(acts_encoded_decoder_view[m][n]),
                      .decoder_o(acts_decoded[m][n])
                      );
      end
   end

   tcn_shiftmem
     #(
       .DEPTH(TCN_WIDTH),
       .PHYSICALBITSPERWORD(PHYSICALBITSPERWORD),
       .WEIGHT_STAGGER(WEIGHT_STAGGER)
       ) i_tcn_shiftmem (
                         .clk_i(clk_i),
                         .rst_ni(rst_ni),
                         .data_i(shiftmem_data_in),
                         .save_enable_i(shiftmem_save_enable),
                         .flush_i('0),
                         .set_depth_i(tcn_actmem_set_shift_i),
                         .read_depth_i(tcn_actmem_read_shift_i),
                         .write_depth_i(tcn_actmem_write_shift_i),
                         .data_o(shiftmem_data_out));

endmodule
