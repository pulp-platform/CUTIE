// ----------------------------------------------------------------------
//
// File: actmem_write_controller.sv
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
// The actmem_write_controller manages the writeback of valid computed outputs.
// In essence, it calculates how many words need to be written back and counts addresses

module actmem_write_controller
  #(
    parameter int unsigned N_O = 128,
    parameter int unsigned N_I = 128,
    parameter int unsigned WEIGHT_STAGGER = 8,
    parameter int unsigned K = 3,
    parameter int unsigned IMAGEWIDTH = 224,
    parameter int unsigned IMAGEHEIGHT = 224,
    parameter int unsigned NUMACTMEMBANKSETS = 2,

    parameter int unsigned NUMBANKS = K*WEIGHT_STAGGER,
    parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
    parameter int unsigned PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5, // Round up number of trits per word, cut excess
    parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,
    parameter int unsigned EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2,
    parameter int unsigned EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS,

    parameter int unsigned TOTNUMTRITS = IMAGEWIDTH*IMAGEHEIGHT*N_I,
    parameter int unsigned TRITSPERBANK = (TOTNUMTRITS+NUMBANKS-1)/NUMBANKS,

    parameter int unsigned NUMWRITEBANKS = N_O/(N_I/WEIGHT_STAGGER),
    parameter int unsigned BANKSETSBITWIDTH = NUMACTMEMBANKSETS > 1 ? $clog2(NUMACTMEMBANKSETS) : 1,
    parameter int unsigned ACTMEMBANKDEPTH = (TRITSPERBANK+EFFECTIVETRITSPERWORD-1)/EFFECTIVETRITSPERWORD,
    parameter int unsigned ACTMEMBANKADDRESSDEPTH = $clog2(ACTMEMBANKDEPTH)
    )
   (
    input logic                                              clk_i,
    input logic                                              rst_ni,

    input logic                                              latch_new_layer_i,
    input logic [$clog2(N_O):0]                              layer_no_i,
    input logic [0:NUMWRITEBANKS-1][PHYSICALBITSPERWORD-1:0] wdata_i,
    input logic                                              valid_i,

    output logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0]     wdata_o,
    output logic [0:NUMBANKS-1]                              write_enable_o,
    output logic [0:NUMBANKS-1][ACTMEMBANKADDRESSDEPTH-1:0]  write_addr_o
    );

   logic                                                     init_q;
   logic [ACTMEMBANKADDRESSDEPTH-1:0]                        addresscounter_q, addresscounter_d;
   logic [$clog2(NUMBANKS)-1:0]                              bankcounter_q, bankcounter_d;
   logic [$clog2(N_O):0]                                     layer_no_q;
   logic [$clog2(N_O/(N_O/WEIGHT_STAGGER)):0]                numwrites;

   assign numwrites = layer_no_q/(N_O/WEIGHT_STAGGER);

   always_comb begin
      wdata_o = '0;
      write_enable_o = '0;
      write_addr_o = '0;

      addresscounter_d = addresscounter_q;
      bankcounter_d = bankcounter_q;

      if(init_q == 1 && valid_i == 1) begin

         bankcounter_d = (bankcounter_q + numwrites)%NUMBANKS;
         if(bankcounter_d == 0) begin
            addresscounter_d = addresscounter_q + 1;
         end
         for(int i=0;i<2*NUMBANKS;i++) begin
            if(i>=bankcounter_q && i<(bankcounter_q+numwrites)) begin
               if(i>NUMBANKS) begin
                  write_addr_o[i%NUMBANKS] = addresscounter_q + 1;
               end else begin
                  write_addr_o[i%NUMBANKS] = addresscounter_q;
               end
               wdata_o[i%NUMBANKS] = wdata_i[i-bankcounter_q];
               write_enable_o[i%NUMBANKS] = 1;
            end
         end

      end

   end

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         init_q <= 0;
         layer_no_q <= N_O;
         addresscounter_q <= '0;
         bankcounter_q <= '0;
      end else begin
         if(latch_new_layer_i == 1) begin
            init_q <= 1;
            layer_no_q <= layer_no_i;
            addresscounter_q <= '0;
            bankcounter_q <= '0;
         end else begin
            addresscounter_q <= addresscounter_d;
            bankcounter_q <= bankcounter_d;
         end
      end
   end

endmodule
