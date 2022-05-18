// ----------------------------------------------------------------------
//
// File: tern_mult.sv
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
// Ternary multiplier. Takes 2 Bit signed representation of two trits, multiplies them and return 00 for 0, 01 for -1 and 10 for 1
// This is done so adding all -1s and 1 takes only one popcount each.

module ternary_mult
  (
   input logic [1:0]  act_i,
   input logic [1:0]  weight_i,
   output logic [1:0] outp_o
   );

   always_comb begin
      if (act_i == 2'b00 || weight_i == 2'b00)
        outp_o = 2'b00;
      else if (act_i == 2'b01 && weight_i == 2'b01)
        outp_o = 2'b10;
      else if (act_i == 2'b11 && weight_i == 2'b01)
        outp_o = 2'b01;
      else if (act_i == 2'b11 && weight_i == 2'b11)
        outp_o = 2'b10;
      else if (act_i == 2'b01 && weight_i == 2'b11)
        outp_o = 2'b01;
      else
        outp_o = 'X;
   end

endmodule // ternary_mult
