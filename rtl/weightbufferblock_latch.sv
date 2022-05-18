// ----------------------------------------------------------------------
//
// File: weightbufferblock_latch.sv
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
// Make sure input is stable for clock

// The weightbufferblock is part of each OCU, it is the memory where the kernel for the
// specific NI/NO combination of each OCU is stored.
// It is implemented with latches for efficiency reasons.

module weightbufferblock
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned K = 3
    )
   (
    input logic [0:K-1][0:K-1][0:N_I-1][1:0]  data_i,
    input logic                               clk_i,
    input logic                               rst_ni,
    input logic                               save_enable_i,
    input logic                               test_enable_i,
    input logic                               flush_i,
    output logic [0:K-1][0:K-1][0:N_I-1][1:0] data_o
    );

   logic [0:K-1][0:K-1][0:N_I-1][1:0]         latch_q, latch_d;
   logic                                      gate_clock;

   assign latch_d = data_i;
   assign data_o = latch_q;
   assign gate_clock = !(save_enable_i || test_enable_i);

   always_latch begin

      if(~rst_ni) begin
         latch_q <= '0;
      end

      else if (clk_i == 1'b0) begin
         if (flush_i == 1) begin
            latch_q <= '0;
         end else if(!gate_clock) begin
            latch_q <= latch_d;
         end
      end


   end // always_ff @

endmodule
