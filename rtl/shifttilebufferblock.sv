// ----------------------------------------------------------------------
//
// File: shifttilebufferblock.sv
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
// Implementation of the tilebuffer block with flipflops.
// The tilebufferblock is a memory written in a FIFO-manner
// which returns outputs like a shift-register

module shifttilebufferblock
  #(
    parameter int unsigned N_I = 256,
    parameter int unsigned DEPTH = 3
    )
   (
    input logic [0:N_I-1][1:0]             data_i,
    input logic                            clk_i,
    input logic                            rst_ni,
    input logic                            save_enable_i,
    input logic                            flush_i,
    output logic [0:DEPTH-1][0:N_I-1][1:0] data_o
    );

   logic [0:DEPTH-1][0:N_I-1][1:0]         mem_reg_q, mem_reg_d;
   logic [$clog2(DEPTH)-1:0]               curr_depth_d, curr_depth_q;
   logic                                   gate_clock;

   always_comb begin
      mem_reg_d = mem_reg_q;
      mem_reg_d[curr_depth_q] = data_i;
      curr_depth_d = (curr_depth_q + 1)%DEPTH;

      if(flush_i) begin
         mem_reg_d = '0;
      end

      for(int i = 0; i < DEPTH; i++) begin
         data_o[i] = mem_reg_q[(i + curr_depth_q)%DEPTH];
      end
   end

   assign gate_clock = !(save_enable_i || flush_i);

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         mem_reg_q <= '0;
         curr_depth_q <= '0;
      end else begin
         if (!gate_clock) begin
            mem_reg_q <= mem_reg_d;
            curr_depth_q <= curr_depth_d;
         end
      end
   end // always_ff @

endmodule
