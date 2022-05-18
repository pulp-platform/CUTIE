// Copyright 2017, 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Date: 13.10.2017
// Description: SRAM Behavioral Model

module sram_weightmem
  import enums_linebuffer::*;
   import enums_conv_layer::*;
   import cutie_params::*;
   #(
     parameter int unsigned WEIGHT_STAGGER = cutie_params::WEIGHT_STAGGER,
     parameter int unsigned K = cutie_params::K,
     parameter int unsigned N_I = cutie_params::N_I,
     parameter int unsigned IMAGEWIDTH = cutie_params::IMAGEWIDTH,
     parameter int unsigned IMAGEHEIGHT = cutie_params::IMAGEHEIGHT,
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
       input logic [$clog2(NUM_WORDS)-1:0] addr_i,
       input logic [DATA_WIDTH-1:0]        wdata_i,
       input logic [DATA_WIDTH-1:0]        be_i,
       //input logic         be_i,
       output logic [DATA_WIDTH-1:0]       rdata_o
       );
   localparam ADDR_WIDTH = $clog2(NUM_WORDS);

   logic [DATA_WIDTH-1:0]                  ram [NUM_WORDS-1:0];
   logic [ADDR_WIDTH-1:0]                  raddr_q;
   logic                                   valid_q, valid_d;


   logic [DATA_WIDTH-1:0]                  be;
   always_comb begin
      if(be_i == '1) begin
         be = '1;
      end
   end

   always_comb begin
      if (req_i && !we_i) begin
         valid_d = '1;
      end else begin
         valid_d = '0;
      end   end

   // 1. randomize array
   // 2. randomize output when no request is active
   always_ff @(posedge clk_i) begin
      if(~rst_ni) begin
         valid_q <= '0;
         raddr_q <= '0;
      end else begin
         valid_q <= valid_d;
         if (req_i) begin
            if (!we_i) begin
               raddr_q <= addr_i;
            end else begin
               for (int i = 0; i < DATA_WIDTH; i++) begin
                  if (be[i])  begin
                     ram[addr_i][i] <= wdata_i[i];
                  end
               end
            end
         end // if (req_i)
      end
   end // always_ff @

   always_comb begin
      if(valid_q == '1) begin
         rdata_o = ram[raddr_q];
      end else begin
         rdata_o = 'X;
      end
   end

endmodule
