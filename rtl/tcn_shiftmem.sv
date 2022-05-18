// ----------------------------------------------------------------------
//
// File: tcn_shiftmem.sv
//
// Created: 06.05.2022
//
// Copyright (C) 2022, ETH Zurich and University of Bologna.
//
// Authors:
// Tim Fischer, ETH Zurich
// Moritz Scherer, ETH Zurich
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

module tcn_shiftmem
  #(
    parameter int unsigned DEPTH = 48,
    parameter int unsigned PHYSICALBITSPERWORD = 80,
    parameter int unsigned WEIGHT_STAGGER = 2
    )
   (
    input logic                                               clk_i,
    input logic                                               rst_ni,
    input logic [0:WEIGHT_STAGGER-1][PHYSICALBITSPERWORD-1:0] data_i,
    input logic [0:WEIGHT_STAGGER-1]                          save_enable_i,
    input logic                                               flush_i,
    input logic                                               set_depth_i,
    input logic [$clog2(DEPTH)-1:0]                           read_depth_i,
    input logic [$clog2(DEPTH)-1:0]                           write_depth_i,
    output logic [0:DEPTH-1][PHYSICALBITSPERWORD-1:0]         data_o
    );

   logic [0:DEPTH-1][PHYSICALBITSPERWORD-1:0]                 mem_reg_q, mem_reg_d;
   logic [$clog2(DEPTH)-1:0]                                  read_depth_q, read_depth_d;
   logic [$clog2(DEPTH)-1:0]                                  write_depth_q, write_depth_d;

   always_comb begin
      mem_reg_d = mem_reg_q;

      read_depth_d = read_depth_q;
      write_depth_d = write_depth_q;

      for(int i = 0; i < WEIGHT_STAGGER; i++) begin
         if(save_enable_i[i]) begin
            read_depth_d = (read_depth_d + save_enable_i[i]) % DEPTH;
            write_depth_d = (write_depth_d + save_enable_i[i]) % DEPTH;
            mem_reg_d[write_depth_q + i] = data_i[i];
         end
      end

      if(flush_i) begin
         mem_reg_d = '0;
      end

      if(set_depth_i) begin
         read_depth_d = read_depth_i;
         write_depth_d = write_depth_i;
      end

      for(int i = 0; i < DEPTH; i++) begin
         data_o[i] = mem_reg_q[(i + read_depth_q)%DEPTH];
      end
   end

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         for(int i = 0; i < DEPTH; i++) begin
            mem_reg_q[i] <= {10{8'b11111001}};
         end
         read_depth_q <= '0;
         write_depth_q <= '0;
      end else begin
         mem_reg_q <= mem_reg_d;
         read_depth_q <= read_depth_d;
         write_depth_q <= write_depth_d;
      end
   end // always_ff @

endmodule
