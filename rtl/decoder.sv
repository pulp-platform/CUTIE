// ----------------------------------------------------------------------
//
// File: decoder.sv
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
// The decoder module is purely combinatorial and translates an 8-Bit input tuple
// To 5 Trits that are used for internal computation. Encoding is done in order to save storage space.
// The 5 Trit representation is unique, the 8 Bit representation is not.

module decoder
  (
   input logic [7:0]       decoder_i,
   output logic [4:0][1:0] decoder_o
   );
   logic [9:0]             x;
   logic [9:0]             y;
   logic [2:0]             z;

   logic [7:0]             b;
   logic [9:0]             t;

   assign b = decoder_i;
   assign decoder_o = {>>{t}};

   always_comb begin

      z[0] = ~b[6] & ~b[1] & b[5];
      z[1] = ~b[3] & b[2];
      z[2] = ~b[0] & b[1];

      y[8] = b[0] & b[7] & b[6];
      y[9] = ~(~b[3] | b[2]);
      y[3] = b[0] & ~b[1] & b[3];
      y[4] = ~(b[0] | ~b[4]);
      y[5] = ~b[0] & ~b[1];
      y[6] = ~b[0] & b[3];
      y[1] = b[0] & b[1];
      y[0] = ~b[1] & ~y[9] | b[7] & z[0] | y[5] | b[1] & y[9] & b[7];
      y[2] = ~y[4] & (b[0] ^ b[1]) & ~b[3] & ~b[2];

      x[0] = y[1] & b[2];
      x[1] = (~b[0] | b[5]) & ~b[6] & ~b[1] & b[2] | ~b[3] | x[0];
      x[2] = z[2] & b[3] & b[2];
      x[3] = (b[0] & z[0] | z[2]) & ~b[7] & y[9];
      x[4] = y[2] & ~b[5] | z[1] | y[1];
      x[5] = y[3] & ~b[6] & ~b[5] | y[6] & b[2] & b[6] | y[5] & y[9];

      y[7] = x[2] & ~b[6];

      x[6] = (y[8] | b[1] & ~b[4]) & b[2] | y[8] & ~b[4] & b[3] | y[7] | b[0] & z[1] | y[1];
      x[7] = ~b[0] & ~b[2] & (~b[1] | b[3]) | y[2] & b[5];

      x[8] = (~b[7] | ~y[9]) & y[1] | y[7];
      x[9] = y[6] & ~b[2] | y[4] & ~b[3] | x[2] & b[6] & b[4] | y[5] | y[3] & ~b[7] & b[6];

      t[0] = x[0] | y[0];
      t[1] = b[4] & y[0] | b[3] & x[0];
      t[2] = x[8] | x[9];
      t[3] = b[5] & x[9] | b[4] & x[8];
      t[4] = x[6] | x[7];
      t[5] = b[6] & x[7] | b[5] & x[6];
      t[6] = x[4] | x[5];
      t[7] = b[7] & x[5] | b[6] & x[4];
      t[8] = x[1] | x[3];
      t[9] = b[4] & x[3] | b[7] & x[1];

   end // always_comb

endmodule
