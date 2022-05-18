// ----------------------------------------------------------------------
//
// File: actmem2lb_controller.sv
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

module actmem2lb_controller
  import enums_conv_layer::*;
   import enums_linebuffer::*;
   #(
     parameter int unsigned N_I = 128,
     parameter int unsigned K = 3,
     parameter int unsigned IMAGEWIDTH = 32,
     parameter int unsigned IMAGEHEIGHT = 32,
     parameter int unsigned COLADDRESSWIDTH = $clog2(IMAGEWIDTH),
     parameter int unsigned ROWADDRESSWIDTH = $clog2(IMAGEHEIGHT),
     parameter int unsigned WEIGHT_STAGGER = N_I/64,
     parameter int unsigned NUMACTMEMBANKSETS = 3,

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
     parameter int unsigned SPLITWIDTH = $clog2(WEIGHT_STAGGER)+1)
   (
    input logic                                        clk_i,
    input logic                                        rst_ni,

    input logic                                        new_layer_i,
    // Data stays constant over an entire layer
    input logic unsigned [COLADDRESSWIDTH:0]           layer_imagewidth_i,
    input logic unsigned [ROWADDRESSWIDTH:0]           layer_imageheight_i,
    input logic unsigned [$clog2(N_I):0]               layer_ni_i,

    input logic                                        ready_i, // receives ok from front controller
    input logic                                        valid_i, // ActMem handshake signal
    input logic unsigned [COLADDRESSWIDTH-1:0]         write_col_i,
    input logic unsigned [ROWADDRESSWIDTH-1:0]         write_row_i,
    input logic                                        wrap_around_save_enable_i,

    output logic [0:NUMBANKS-1]                        read_enable_vector_o,
    output logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0] read_addr_o,
    output logic [LEFTSHIFTBITWIDTH-1:0]               left_shift_o,
    output logic [SPLITWIDTH-1:0]                      scatter_coefficient_o
    );

   logic [0:NUMBANKS-1]                                read_enable_vec;
   logic [0:NUMBANKS-1][$clog2(BANKDEPTH)-1:0]         read_addr;

   logic unsigned [$clog2(NUMBANKS)-1:0]               bank_index_q, bank_index_d;
   logic unsigned [$clog2(BANKDEPTH)-1:0]              bank_depth_q, bank_depth_d;
   logic unsigned [$clog2(K)-1:0]                      pixels2write;
   logic unsigned [$clog2(WEIGHT_STAGGER):0]           pixelwidth_q;

   assign read_enable_vector_o = read_enable_vec;
   assign read_addr_o = read_addr;
   assign left_shift_o = bank_index_q;
   assign scatter_coefficient_o = pixelwidth_q;

   always_comb begin
      pixels2write = '0;
      bank_index_d = bank_index_q;
      bank_depth_d = bank_depth_q;

      // The memory layout of the actmem does not distinguish between neighbouring K pixels
      // and K pixels which are wrapped around in the feature map. Normally, just the next K pixels
      // can be loaded from Actmem. Hovewever, in some cases wrap around save is disabled and
      // only the last pixels from the current line are loaded
      if(write_col_i + K > layer_imagewidth_i && !wrap_around_save_enable_i) begin
         pixels2write = layer_imagewidth_i - write_col_i;
      end else begin
         pixels2write = K;
      end


      if(new_layer_i) begin
         bank_index_d = 0;
         bank_depth_d = 0;
      end else if(ready_i) begin

         // The controller just counts up to the number of banks, once it overflows
         // the address/depth increases by one
         if(bank_index_q + pixels2write * pixelwidth_q >= NUMBANKS) begin
            bank_index_d = (bank_index_q + pixels2write * pixelwidth_q) - NUMBANKS;
            bank_depth_d = bank_depth_q + 1;
         end else begin
            bank_index_d = bank_index_q + pixels2write * pixelwidth_q;
            bank_depth_d = bank_depth_q;
         end
      end // else: !if(new_layer_i || !init_q)

      read_enable_vec = '0;
      read_addr = '0;

      if(ready_i) begin

         // pixels2write pixels have to be read from actmemory in this cycle. this requires reading
         // from pixels2write * pixelwidth banks. The first of these pixels is stored at
         // actmem[bank_index_q][bank_depth_q]. if the first index overflows we start from zero and
         // increment bank_depth_q by one
         for(int k = 0; k < pixels2write * pixelwidth_q; k++) begin
            if(bank_index_q + k >= NUMBANKS) begin
               read_enable_vec[(bank_index_q + k) - NUMBANKS] = 1'b1;
               read_addr[(bank_index_q + k) - NUMBANKS] = bank_depth_q + 1;
            end else begin
               read_enable_vec[bank_index_q + k] = 1'b1;
               read_addr[bank_index_q + k] = bank_depth_q;
            end
         end
      end

   end // always_comb

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         bank_index_q <= '0;
         bank_depth_q <= '0;
         pixelwidth_q <= '0;
      end else begin
         bank_index_q <= bank_index_d;
         bank_depth_q <= bank_depth_d;
         pixelwidth_q <= ((layer_ni_i + N_I/WEIGHT_STAGGER - 1) / (N_I/WEIGHT_STAGGER));
      end
   end // always_ff @ (posedge clk_i, negedge rst_ni)
endmodule // actmem_read_controller
