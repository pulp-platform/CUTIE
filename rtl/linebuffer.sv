// ----------------------------------------------------------------------
//
// File: linebuffer.sv
//
// Created: 06.05.2022
//
// Copyright (C) 2022, ETH Zurich and University of Bologna.
//
// Authors:
// Moritz Scherer, ETH Zurich
// Tim Fischer, ETH Zurich
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
// The linefbuffer module buffers the loaded activations from the activation memory.
// For each window, KxK pixels have to be loaded.
// Pixels are loaded line by line, this way there are no bank conflicts when loading.
// They are buffered in a ImageWidthxK deep buffermatrix.

// Output windows are defined by their central pixel, i.e. the KxK pixels are chosen around the central pixel
// The wrap_around signals are used to define behaviour when the KxK chosen pixels are partially outside of the buffer
// If wrap_around is disabled, the outside pixels are zeroed.

// The buffer addresses consist of row and column addresses
// If central pixel is located at the edge of the tilebuffer,
// the outside pixels will automatically be padded with zeros (same padding)
// For the case of valid padding, the addresses should always be between [(K-1)/2,(K-1)/2] and [(K-1)/2, IMAGEWIDTH-(K_1)/2]

// Example for same padding: (K=3, IMW=9, K=3)

// read_address_col = 0, read_address_row = 0
// Buffer:
// | 1| 2| 3| 4| 5| 6| 7| 8| 9|
// |10|11|12|13|14|15|16|17|18|
// |19|20|21|22|23|24|25|26|27|
// Window:
// | 0| 0| 0|
// | 0| 1| 2|
// | 0|10|11|

// read_address_col = 8, read_address_row = 2
// Buffer:
// | 1| 2| 3| 4| 5| 6| 7| 8| 9|
// |10|11|12|13|14|15|16|17|18|
// |19|20|21|22|23|24|25|26|27|
// Window:
// |17|18| 0|
// |26|27| 0|
// | 0| 0| 0|


//

module linebuffer
  #(
    parameter int unsigned N_I = 256,
    parameter int unsigned K = 3,
    parameter int unsigned IMAGEWIDTH = 32,
    parameter int unsigned IMAGEHEIGHT = 32,
    parameter int unsigned COLADDRESSWIDTH = $clog2(IMAGEWIDTH),
    parameter int unsigned ROWADDRESSWIDTH = $clog2(IMAGEHEIGHT),
    parameter int unsigned TBROWADDRESSWIDTH = $clog2(K)
    )
   (

    input logic                                  clk_i,
    input logic                                  rst_ni,

    input logic [0:K-1][0:N_I-1][1:0]            acts_i,

    input logic                                  flush_i,
    input logic                                  valid_i,

    input logic [COLADDRESSWIDTH:0]              layer_imagewidth_i,
    input logic [ROWADDRESSWIDTH:0]              layer_imageheight_i,

    input logic                                  write_enable_i,
    input logic                                  wrap_around_save_enable_i,
    // Leftmost column save address; (K-1) right neighboring cells are written to, too
    input logic unsigned [COLADDRESSWIDTH-1:0]   write_col_i,

    input logic                                  read_enable_i,
    // Central linebuffer column address of KxK pixels [0, IMAGEWIDTH]
    input logic unsigned [COLADDRESSWIDTH-1:0]   read_col_i,
    // Central linebuffer row address of KxK pixels [0, K], should always be (K-1)/2 unless same padding is active
    // For valid padding, input should look like 0,1,2,2,...,2,2,3,4 (for K = 5)
    input logic unsigned [TBROWADDRESSWIDTH-1:0] read_row_i,
    output logic [0:K-1][0:K-1][0:N_I-1][1:0]    acts_o
    );


   logic [0:IMAGEWIDTH-1][0:N_I-1][1:0]          inputs;
   logic [0:IMAGEWIDTH-1][0:K-1][0:N_I-1][1:0]   output_matrixview;
   logic [0:IMAGEWIDTH-1]                        save_enable_vector;
   logic                                         write_enable_q;
   logic unsigned [COLADDRESSWIDTH-1:0]          write_col_q;
   logic                                         wrap_around_save_enable_q;

   logic signed [0:K-1][COLADDRESSWIDTH:0]       check_valid_col;
   logic signed [0:K-1][ROWADDRESSWIDTH:0]       check_valid_row;

   always_comb begin
      save_enable_vector = '0;
      inputs = '0;

      // Make sure that all K input blocks
      // 1) are save enabled
      // 2) address does not fall outside of Linebuffer
      // 3) connect act inputs to correct block inputs
      if(write_enable_q && valid_i) begin
         for(int k = 0; k < K; k++) begin
            if(write_col_q + k < layer_imagewidth_i) begin
               save_enable_vector[write_col_q + k] = 1'b1;
               inputs[write_col_q + k] = acts_i[k];
            end else if (wrap_around_save_enable_q) begin
               save_enable_vector[(write_col_q + k) - layer_imagewidth_i] = 1'b1;
               inputs[(write_col_q + k) - layer_imagewidth_i] = acts_i[k];
            end
         end
      end

      // set all act outputs to zeros.
      // If padding == SAME only inside pixels will be overwritten.
      // If padding == VALID all pixels will be overwritten
      acts_o = '0;
      check_valid_col = '0;
      check_valid_row = '0;

      if(read_enable_i) begin
         for(int kx = 0; kx < K; kx++) begin
            for(int ky = 0; ky < K; ky++) begin
               check_valid_col[kx] = read_col_i - (K-1)/2 + kx;
               check_valid_row[ky] = read_row_i - (K-1)/2 + ky;

               // Check if calculated column and row address fall outside of tilebuffer
               // which should only happen if padding == SAME
               if((check_valid_col[kx] >= 0) && (check_valid_col[kx] < layer_imagewidth_i) && (check_valid_row[ky] >= 0) && (check_valid_row[ky] < K)) begin

                  // check_valid_row is not the physical row as the tile buffer is not actually a shift register
                  // but more like a vertical ring buffer, Therefore the row has to be translated first
                  acts_o[kx][ky] = output_matrixview[check_valid_col[kx]][check_valid_row[ky]];
               end
            end // for (int ky = 0; ky < K; ky++)
         end // for (int kx = 0; kx < K; kx++)
      end // if (read_enable_i)
   end

   genvar m;
   generate
      for (m=0;m<IMAGEWIDTH;m++) begin
         shifttilebufferblock
             #(
               .DEPTH(K),
               .N_I(N_I)
               ) block (
                        .data_i(inputs[m]),
                        .clk_i(clk_i),
                        .rst_ni(rst_ni),
                        .flush_i(flush_i),
                        .save_enable_i(save_enable_vector[m]),
                        .data_o(output_matrixview[m])
                        );
      end // for (n=0;n<K;n++)
   endgenerate

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(!rst_ni) begin
         write_enable_q <= '0;
         write_col_q <= '0;
         wrap_around_save_enable_q <= '0;
      end else begin
         write_enable_q <= write_enable_i;
         write_col_q <= write_col_i;
         wrap_around_save_enable_q <= wrap_around_save_enable_i;
      end
   end
endmodule
