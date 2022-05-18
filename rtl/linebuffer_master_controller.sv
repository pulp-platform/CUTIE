// ----------------------------------------------------------------------
//
// File: linebuffer_master_controller.sv
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
//
// This controller handles the read and write processes to the tilebuffer. It has to make sure
// that pixels are written before they can be read and that no pixels are overwritten before
// they have been read. From both the read and the write controller, it receives their current
// read/write addresses (col: ..._address_i, row: lines_..._i) and predicts the next addresses.
// It can enable and disable the read and write process if a conflict would occur. Moreover,
// It also signals to the write controller and the tilebuffer if the K pixels to be saved
// are wrapped around the right edge or not.



module linebuffer_master_controller
  import enums_rw_state::*;
   import enums_conv_layer::*;
   #(
     parameter int unsigned N_I = 256,
     parameter int unsigned K = 3,
     parameter int unsigned IMAGEWIDTH = 32,
     parameter int unsigned IMAGEHEIGHT = 32,
     parameter int unsigned COLADDRESSWIDTH = $clog2(IMAGEWIDTH),
     parameter int unsigned ROWADDRESSWIDTH = $clog2(IMAGEHEIGHT),
     parameter int unsigned TCN_WIDTH = 24
     )
   (
    input logic                                  clk_i,
    input logic                                  rst_ni,
    input logic                                  new_layer_i,

    input logic                                  valid_i,
    input logic                                  ready_i,
    // Data stays constant over an entire layer
    input logic unsigned [$clog2(K)-1:0]         layer_stride_width_i,
    input logic unsigned [$clog2(K)-1:0]         layer_stride_height_i,
    input                                        enums_conv_layer::padding_type layer_padding_type_i,
    input logic unsigned [COLADDRESSWIDTH:0]     layer_imagewidth_i,
    input logic unsigned [ROWADDRESSWIDTH:0]     layer_imageheight_i,
    input logic unsigned [$clog2(N_I):0]         layer_ni_i,
    input logic                                  layer_is_tcn_i,
    input logic unsigned [$clog2(TCN_WIDTH)-1:0] layer_tcn_width_mod_dil_i,
    input logic unsigned [$clog2(K)-1:0]         layer_tcn_k_i,

    output logic                                 ready_read_o,
    output logic                                 ready_write_o,
    output logic [COLADDRESSWIDTH-1:0]           read_col_o,
    output logic [ROWADDRESSWIDTH-1:0]           read_row_o,
    output logic [COLADDRESSWIDTH-1:0]           write_col_o,
    output logic [ROWADDRESSWIDTH-1:0]           write_row_o,
    output logic                                 wrap_around_save_enable_o,
    output logic                                 done_o,
    output logic                                 flush_o
    );

   enums_rw_state::rw_state state_q, state_d;
   logic                                         wrap_around_save_enable_q, wrap_around_save_enable_d;
   logic unsigned [COLADDRESSWIDTH-1:0]          read_col_q, read_col_d;
   logic unsigned [ROWADDRESSWIDTH-1:0]          read_row_q, read_row_d;
   logic unsigned [COLADDRESSWIDTH-1:0]          write_col_q, write_col_d;
   logic unsigned [ROWADDRESSWIDTH:0]            write_row_q, write_row_d;

   logic signed [ROWADDRESSWIDTH:0]              row_difference;
   logic signed [COLADDRESSWIDTH:0]              col_difference;
   logic unsigned [ROWADDRESSWIDTH:0]            rows2read;
   logic unsigned [COLADDRESSWIDTH-1:0]          tcn_last_col;
   logic unsigned [ROWADDRESSWIDTH:0]            tcn_last_row;
   logic                                         read_cond, write_cond;
   logic                                         done_q2, done_q1, done_d;
   logic                                         init_q;
   logic                                         acts_req_q, acts_req_d;

   logic unsigned [$clog2(K)-1:0]                stride_width_q;
   logic unsigned [$clog2(K)-1:0]                stride_height_q;
   enums_conv_layer::padding_type padding_type_q;
   logic unsigned [COLADDRESSWIDTH:0]            imagewidth_q;
   logic unsigned [ROWADDRESSWIDTH:0]            imageheight_q;
   logic unsigned [$clog2(N_I):0]                ni_q;
   logic                                         is_tcn_q;
   logic unsigned [COLADDRESSWIDTH-1:0]          tcn_width_mod_dil_q;
   logic unsigned [$clog2(K)-1:0]                tcn_k_q;


   assign wrap_around_save_enable_o = wrap_around_save_enable_q;
   assign read_col_o = read_col_q;
   assign read_row_o = read_row_q;
   assign write_col_o = write_col_q;
   assign write_row_o = write_row_q;
   assign ready_read_o = state_q[0];
   assign ready_write_o = state_q[1];
   assign done_o = (state_q == NONE) && done_q2;
   assign flush_o = new_layer_i;

   always_comb begin

   end // always_comb

   always_comb begin
      read_col_d = '0;
      read_row_d = '0;
      write_col_d = '0;
      write_row_d = '0;
      rows2read = '0;
      acts_req_d = ready_write_o;

      // This block of code calculates the next read/write column and row addresses.
      // These addresses are needed to determine whether there will be a read/write conflict
      // next cycle. If the controllers are not allowed to read/write the addresses stay the same
      if(ready_write_o && !(acts_req_q && !valid_i)) begin
         if(write_col_q + K >= imagewidth_q) begin
            write_row_d = write_row_q + 1;

            // Tiles of K pixels can be wrapped around the right edge if enabled,
            // otherwise the overlapping pixels are just ignored
            if(wrap_around_save_enable_q) begin
               write_col_d = (write_col_q + K) - imagewidth_q;
            end else begin
               write_col_d = 0;
            end
         end else begin // if (save_address_i + K >= layer_imagewidth_i)
            write_col_d = write_col_q + K;
            write_row_d = write_row_q;
         end // else: !if(save_address_i + K >= layer_imagewidth_i)
      end else begin // if (ready_read_o)
         write_col_d = write_col_q;
         write_row_d = write_row_q;
      end // else: !if(ready_read_o)

      unique case(padding_type_q)
        SAME : rows2read = imageheight_q;
        VALID : rows2read = imageheight_q - (K-1)/2; // row index starts with (K-1)/2
        default: ;
      endcase // case (layer_padding_type_i)

      // TODO: rename layer_tcn_dilation_i, to modulo... modulo operation is too
      // expensive, hence modulo is done by software
      tcn_last_col = tcn_width_mod_dil_q;
      // tcn_last_col = tcn_1d_width_i % tcn_dilation_i;
      tcn_last_row = imageheight_q - (tcn_k_q - 1) + ((tcn_last_col == 0)? 1 : 0);

      if(ready_read_o) begin
         unique case(padding_type_q)
           SAME : begin
              if(read_col_q + stride_width_q >= imagewidth_q) begin
                 read_col_d = 0;
                 read_row_d = read_row_q + stride_height_q;
              end else begin
                 read_col_d = read_col_q + stride_width_q;
                 read_row_d = read_row_q;
              end
           end
           VALID : begin
              if(read_col_q + stride_width_q >= imagewidth_q - (K-1)/2) begin
                 read_col_d = (K-1)/2;
                 read_row_d = read_row_q + stride_height_q;
              end else begin
                 read_col_d = read_col_q + stride_width_q;
                 read_row_d = read_row_q;
              end
           end
           default: ;
         endcase // case (padding_type_i)
      end else begin // if (ready_write_o)
         read_col_d = read_col_q;
         read_row_d = read_row_q;
      end


      wrap_around_save_enable_d = 0;
      row_difference = write_row_q - read_row_d;
      col_difference = write_col_q - read_col_d;


      // Normally wrap around save should be enabled as it speeds up the writing process
      // especially for small feature maps. But there are cases where the overlapping pixels
      // (of the K pixels to be written to the tilebuffer) might overwrite pixels which still
      // have to be read. Therefore wrap around save is disabled in some cases
      if(imagewidth_q < K) begin
         wrap_around_save_enable_d = 0;
      end
      else if(write_col_d + K > imagewidth_q) begin
         wrap_around_save_enable_d = 1;

         // If writing process is finished or if overlapping pixels overwrite pixels to be read,
         // disable wrap around save
         if(write_row_d + 1 >= imageheight_q ||
            (read_col_d < (write_col_d + K) % imagewidth_q + (K-1)/2
             && write_row_d > read_row_d)) begin
            wrap_around_save_enable_d = 0;
         end
      end

      // Based on the read and write addresses, the controller determines whether reading
      // and writing to the tilebuffer is aloud i.e. if no pixels are overwritten before they are read
      // and no pixels are read before they are written.
      read_cond = 0;
      write_cond = 0;
      done_d = done_q1;
      state_d = NONE;

      //$display("write_row_d: %d, read_row_d: %d, row_difference: %d, col_difference: %d", write_row_d, read_row_d, row_difference, col_difference);
      if(!ready_i || done_q1) begin
         read_cond = 0;
      end

      else if(is_tcn_q &&
              read_row_d == tcn_last_row &&
              read_col_d == tcn_last_col) begin
         read_cond = 0;
         done_d = 1;
      end

      // If writing is finished for feature map and reading is on the last line
      // -> enable reading
      else if(write_row_q == imageheight_q &&
              read_row_d == rows2read - 1) begin
         read_cond = 1;
         //$display("readcase1");
      end
      // If the last line has been read
      // -> disable reading
      else if(read_row_d >= rows2read) begin
         read_cond = 0;
         done_d = 1;
         //$display("readcase2");
      end
      // If the write controller is exactly (K-1)/2 lines ahead of reading
      // and more than (K-1)/2 columns ahead, we can savely say that no read/write conflict occurs.
      // This handles the case where the read process is to left of the write process
      // -> enable reading
      else if(row_difference == $signed((K-1)/2) &&
              col_difference > $signed((K-1)/2)) begin
         read_cond = 1;
         //$display("readcase3");

      end
      // If the write controller is ahead by more than (K-1)/2 lines
      // -> enable reading
      else if(row_difference > $signed((K-1)/2)) begin
         read_cond = 1;
         //$display("readcase4");
      end else begin
         //$display("noreadcase");
      end

      // If last lines has been written
      // -> disable writing
      if (write_row_d == imageheight_q) begin
         write_cond = 0;
         //$display("writecase1");
      end
      // If the write controller is behind the read controller.
      // This can occur in the begining for the first few lines and
      // if stride_height > 1
      // enable writing
      else if (row_difference < $signed((K-1)/2)) begin
         write_cond = 1;
         //$display("writecase2");
      end
      // If the write controller is ahead by (K-1)/2 lines, it means that for the current line and
      // to the right of the current save address, all pixels can be written without conflicting with
      // the read controller. This models the case where the read process is left of the write process
      // -> enable writing
      else if (row_difference == $signed((K-1)/2) &&
               write_row_d == write_row_q) begin
         write_cond = 1;
         //$display("writecase3");
      end
      // If the writing address is ahead by more than (K-1)/2 lines it means that
      // the write address is catching up to the read and it has to be made sure that
      // nothing is overwritten too early. This happens if the column difference is smaller than
      // K (writing) + (K-1)/2 (reading)
      // -> disable writing
      else if (row_difference > $signed((K-1)/2) &&
               -col_difference >= $signed(2*K + (K-1)/2)) begin
         //$display("writecase4");
         write_cond = 1;
      end else begin
         //$display("nowritecase");
      end

      // STATES: {NONE=2'b00, READ=2'b01, WRITE=2'b10, READ_WRITE=2'b11} rw_state;
      state_d = enums_rw_state::rw_state'({write_cond, read_cond});
      //$cast(state_d, {write_cond, read_cond});

      if (new_layer_i) begin
         if(layer_is_tcn_i) begin
            write_row_d = layer_tcn_k_i - 1;
            read_row_d = (K-1)/2;
         end else begin
            write_row_d = '0;
            read_row_d = (layer_padding_type_i)? 0 : (K-1)/2;
         end
      end
   end // always_comb


   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         state_q <= NONE;
         wrap_around_save_enable_q <= 0;
         read_col_q <= '0;
         read_row_q <= '0;
         write_col_q <= '0;
         write_row_q <= '0;
         acts_req_q <= '0;
         done_q1 <= 1'b1;
         done_q2 <= 1'b1;
         init_q <= 1'b0;
         stride_width_q <= '0;
         stride_height_q <= '0;
         padding_type_q <= SAME;
         imagewidth_q <= '0;
         imageheight_q <= '0;
         ni_q <= '0;
         is_tcn_q <= '0;
         tcn_width_mod_dil_q <= '0;
         tcn_k_q <= '0;
      end else begin
         wrap_around_save_enable_q <= wrap_around_save_enable_d;
         acts_req_q <= acts_req_d;
         done_q2 <= done_q1;
         if(new_layer_i) begin
            read_col_q <= (layer_padding_type_i)? 0 : (K-1)/2;
            write_col_q <= 0;
            state_q <= WRITE;
            done_q1 <= 1'b0;
            done_q2 <= 1'b0;
            init_q <= 1'b1;
            stride_width_q <= layer_stride_width_i;
            stride_height_q <= layer_stride_height_i;
            padding_type_q <= layer_padding_type_i;
            imagewidth_q <= layer_imagewidth_i;
            imageheight_q <= layer_imageheight_i;
            ni_q <= layer_ni_i;
            is_tcn_q <= layer_is_tcn_i;
            tcn_width_mod_dil_q <= layer_tcn_width_mod_dil_i;
            tcn_k_q <= layer_tcn_k_i;
            write_row_q <= write_row_d;
            read_row_q <= read_row_d;
         end else if(init_q) begin
            done_q1 <= done_d;
            state_q <= state_d;
            read_col_q <= read_col_d;
            read_row_q <= read_row_d;
            write_col_q <= write_col_d;
            write_row_q <= write_row_d;
         end
      end
   end

endmodule
