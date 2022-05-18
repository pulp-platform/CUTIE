// ----------------------------------------------------------------------
//
// File: sram_weightmem_latch.sv
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

module sram_weightmem
  import enums_linebuffer::*;
   import enums_conv_layer::*;
   import cutie_params::*;
   #(
     parameter int unsigned N_I = 512,
     parameter int unsigned K = 3,
     parameter int unsigned WEIGHT_STAGGER = 8,
     parameter int unsigned BANKDEPTH = cutie_params::WEIGHTBANKDEPTH,

     parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
     parameter int unsigned PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5, // Round up number of trits per word; cut excess
     parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,

     parameter int unsigned NUM_WORDS = BANKDEPTH,
     parameter int unsigned DATA_WIDTH = PHYSICALBITSPERWORD

     )(
       input logic                         clk_i,
       input logic                         rst_ni,
       input logic                         req_i,
       input logic                         we_i,
       input logic [$clog2(BANKDEPTH)-1:0] addr_i,
       input logic [DATA_WIDTH-1:0]        wdata_i,
       input logic [DATA_WIDTH-1:0]        be_i,
       output logic [DATA_WIDTH-1:0]       rdata_o
       );

   logic [NUM_WORDS-1:0][DATA_WIDTH-1:0]   latch_q;
   logic [$clog2(NUM_WORDS)-1:0]           raddr_q, waddr_q;
   logic                                   write_q, write_d, read;
   logic [DATA_WIDTH-1:0]                  wdata_q, be_q;
   logic [DATA_WIDTH-1:0]                  data_out_q;


   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin

         write_q <= '0;
         raddr_q <= '0;
         waddr_q <= '0;
         wdata_q <= '0;
         be_q <= '0;
         data_out_q <= '0;

      end else begin

         write_q <= write_d;

         if(req_i) begin
            if(!we_i) begin
               raddr_q <= addr_i;
            end else begin
               waddr_q <= addr_i;
               wdata_q <= wdata_i;
               be_q <= be_i;
            end
         end

         if(read) begin
            data_out_q <= latch_q[addr_i];
         end
      end
   end

   always_comb begin
      write_d = req_i & we_i;
      read = req_i & ~we_i;
   end

   always_latch begin
      if(~rst_ni) begin
         latch_q <= '0;
      end else begin
         for(int i=0;i<NUM_WORDS;i++) begin
            if(clk_i == 1'b0 && (write_q == 1'b1 && waddr_q == i)) begin
               latch_q[waddr_q] <= wdata_q;
            end
         end
      end
   end

   assign rdata_o = data_out_q;

endmodule
