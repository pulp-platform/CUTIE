// ----------------------------------------------------------------------
//
// File: lb2ocu_controller.sv
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


module lb2ocu_controller
  import enums_conv_layer::*;
   #(
     parameter int unsigned N_I = 128,
     parameter int unsigned K = 3,
     parameter int unsigned IMAGEWIDTH = 32,
     parameter int unsigned IMAGEHEIGHT = 32,
     parameter int unsigned COLADDRESSWIDTH = $clog2(IMAGEWIDTH),
     parameter int unsigned ROWADDRESSWIDTH = $clog2(IMAGEHEIGHT),
     parameter int unsigned TBROWADDRESSWIDTH = $clog2(K)
     )
   (
    input logic                              clk_i,
    input logic                              rst_ni,

    input logic                              new_layer_i,
    input logic unsigned [$clog2(K)-1:0]     layer_stride_width_i,
    input logic unsigned [$clog2(K)-1:0]     layer_stride_height_i,
    input                                    enums_conv_layer::padding_type layer_padding_type_i,
    input logic unsigned [COLADDRESSWIDTH:0] layer_imagewidth_i,
    input logic unsigned [ROWADDRESSWIDTH:0] layer_imageheight_i,
    input logic unsigned [$clog2(N_I):0]     layer_ni_i,

    input logic                              ready_i,
    input logic [COLADDRESSWIDTH-1:0]        read_col_i,
    input logic [ROWADDRESSWIDTH-1:0]        read_row_i,


    output logic [COLADDRESSWIDTH-1:0]       read_col_o,
    output logic [TBROWADDRESSWIDTH-1:0]     read_row_o
    );

   logic unsigned [TBROWADDRESSWIDTH-1:0]    read_row;

   assign read_col_o = (ready_i)? read_col_i : 0;
   assign read_row_o = (ready_i)? read_row : 0;

   always_comb begin
      read_row = '0;

      /*
       The tilebuffer is initialized with zeros and new lines are written at the bottom
       and then shifted up in a FIFO manner. In case of valid padding no zero padding is required
       which means always the middle row (k-1)/2 of the tilebuffer is the central row. In case of same padding,
       the zero padding of the first (k-1)/2 lines is done by zero initializing and
       the zero padding of the last (k-1)/2 lines is done by setting the central row to (k-1)/2 + 1 (for k=3)
       this way only row index 1 and 2 are read from the tilebuffer and row 3 is automatically filled with zeros
       */
      unique case(layer_padding_type_i)
        SAME : begin
           if (read_row_i >= layer_imageheight_i - (K-1)/2) begin
              read_row = read_row_i - (layer_imageheight_i - K);
           end else begin
              read_row = (K-1)/2;
           end
        end
        VALID : begin
           read_row = (K-1)/2;
        end
        default ;
      endcase // case (layer_padding_type_i)
   end
endmodule
