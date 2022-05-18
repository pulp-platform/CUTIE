// ----------------------------------------------------------------------
//
// File: activationmemory_external_wrapper.sv
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

// The interface features external access that treats the memory like a single RAM bank.
// Access priority is as follows: external access > internal write > internal read
// Colliding requests with lower priority are lost.


module activationmemory_external_wrapper
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned N_O = 512,
    parameter int unsigned K = 3,
    parameter int unsigned WEIGHT_STAGGER = 8,

    parameter int unsigned IMAGEWIDTH = 224,
    parameter int unsigned IMAGEHEIGHT = 224,
    parameter int unsigned TCN_WIDTH = 24,

    parameter int unsigned NUMBANKSETS = 3,

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

    parameter int unsigned BANKSETSBITWIDTH = NUMBANKSETS > 1 ? $clog2(NUMBANKSETS) : 1,
    parameter int unsigned FULLADDRESSBITWIDTH = $clog2(BANKDEPTH*NUMBANKS)
    )
   (
    input logic                                         clk_i,
    input logic                                         rst_ni,

    // Input data

    input logic [BANKSETSBITWIDTH-1:0]                  external_bank_set_i,
    input logic                                         external_we_i,
    input logic                                         external_req_i,
    input logic [FULLADDRESSBITWIDTH-1:0]               external_addr_i,
    input logic [PHYSICALBITSPERWORD-1:0]               external_wdata_i,

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


    output logic [0:NUMBANKS-1]                         valid_o,
    output logic [0:NUMBANKS-1]                         rw_collision_o,
    output logic [0:K-1][0:N_I-1][1:0]                  acts_o,

    output logic [PHYSICALBITSPERWORD-1:0]              external_acts_o,
    output logic                                        external_valid_o
    );

   ///////////////////////////////// COMBINATORIAL SIGNALS /////////////////////////////////

   logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0]        wdata;
   logic [0:NUMBANKS-1]                                 read_enable;
   logic [0:BANKSETSBITWIDTH-1]                         read_enable_bank_set;
   logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]          read_addr;
   logic [0:NUMBANKS-1]                                 write_enable;
   logic [0:BANKSETSBITWIDTH-1]                         write_enable_bank_set;
   logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]          write_addr;
   logic [LEFTSHIFTBITWIDTH-1:0]                        left_shift;
   logic [SPLITWIDTH-1:0]                               scatter_coefficient;
   logic [PHYSICALBITSPERWORD-1:0]                      encoded_acts;

   logic [0:NUMBANKS-1]                                 ready;
   logic [0:NUMBANKS-1]                                 rw_collision;
   logic [0:K-1][0:N_I-1][1:0]                          acts;

   logic [$clog2(NUMBANKS)-1:0]                         bank;
   logic [$clog2(BANKDEPTH)-1:0]                        addr;

   ///////////////////////////////// END COMBINATORIAL SIGNALS /////////////////////////////////

   ///////////////////////////////// SEQUENTIAL SIGNALS /////////////////////////////////

   logic                                                command_source, command_source_q;
   logic                                                prev_external_we;

   ///////////////////////////////// END SEQUENTIAL SIGNALS /////////////////////////////////

   assign bank = external_addr_i%NUMBANKS;
   assign addr = external_addr_i/NUMBANKS;

   always_comb begin

      read_enable = '0;
      write_enable = '0;
      read_addr = '0;
      write_addr = '0;
      wdata = '0;

      // Access arbitration
      if(external_req_i == 1) begin
         command_source = 1;
         read_enable_bank_set = external_bank_set_i;
         write_enable_bank_set = external_bank_set_i;
         read_enable[bank] = ~external_we_i;
         write_enable[bank] = external_we_i;
         read_addr[bank] = addr;
         write_addr[bank] = addr;
         wdata[bank] = external_wdata_i;
         left_shift = bank;
         scatter_coefficient = '0;
      end else begin // if (external_req_i == 1)
         command_source = 0;
         read_enable_bank_set = read_enable_bank_set_i;
         write_enable_bank_set = write_enable_bank_set_i;
         read_enable = read_enable_i;
         write_enable = write_enable_i;
         read_addr = read_addr_i;
         write_addr = write_addr_i;
         wdata = wdata_i;
         left_shift = left_shift_i;
         scatter_coefficient = scatter_coefficient_i;
      end
   end // always_comb

   always_comb begin
      external_acts_o = encoded_acts;
      if(command_source_q == 1) begin
         external_valid_o = ~prev_external_we;
         valid_o = '0;
         rw_collision_o = '1;
         acts_o = '0;
      end else begin
         external_valid_o = 0;
         valid_o = ready;
         rw_collision_o = rw_collision;
         acts_o = acts;
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


   activationmemory_internal_wrapper
     #(
       .N_I(N_I),
       .N_O(N_O),
       .K(K),
       .WEIGHT_STAGGER(WEIGHT_STAGGER),
       .IMAGEWIDTH(IMAGEWIDTH),
       .IMAGEHEIGHT(IMAGEHEIGHT),
       .TCN_WIDTH(TCN_WIDTH),
       .NUMBANKSETS(NUMBANKSETS)
       )
   actmem (
           .clk_i(clk_i),
           .rst_ni(rst_ni),
           .read_enable_i(read_enable),
           .read_enable_bank_set_i(read_enable_bank_set),
           .read_addr_i(read_addr),
           .wdata_i(wdata),
           .write_addr_i(write_addr),
           .write_enable_i(write_enable),
           .write_enable_bank_set_i(write_enable_bank_set),
           .left_shift_i(left_shift),
           .pixelwidth_i(pixelwidth_i),
           .tcn_actmem_set_shift_i(tcn_actmem_set_shift_i),
           .tcn_actmem_read_shift_i(tcn_actmem_read_shift_i),
           .tcn_actmem_write_shift_i(tcn_actmem_write_shift_i),
           .scatter_coefficient_i(scatter_coefficient),
           .ready_o(ready),
           .rw_collision_o(rw_collision),
           .acts_o(acts),
           .encoded_acts_o(encoded_acts)
           );
endmodule
