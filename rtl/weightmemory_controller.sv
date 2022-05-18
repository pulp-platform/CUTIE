// ----------------------------------------------------------------------
//
// File: weightmemory_controller.sv
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
// The weightmemory_internal_wrapper controller controls the loading of weights from N_O/PIPELINEDEPTH modules in lockstep
// Supports shadow loading of weights into the two weight latch banks of the OCU.

// Supports loading of all size of uneven square kernels between (1,1) and (K,K), i.e.
// (1,1),(3,3),(5,5),...

// Weight loading order is Channelsize/(N_I/WEIGHT_STAGGER) x Height x Width x Channel (N_I/WEIGHT_STAGGER)

module weightmemory_controller
  #(
    parameter int unsigned N_I = 512,
    parameter int unsigned N_O = 512,
    parameter int unsigned K = 3,
    parameter int unsigned WEIGHT_STAGGER = 8,
    parameter int unsigned BANKDEPTH = 1024,

    parameter int unsigned PIPELINEDEPTH = 2,

    parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
    parameter int unsigned PHYSICALTRITSPERWORD = (EFFECTIVETRITSPERWORD + 4 / 5) * 5, // Round up number of trits per word, cut excess
    parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,
    parameter int unsigned EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2,
    parameter int unsigned EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS,

    parameter int unsigned NUMDECODERS = PHYSICALBITSPERWORD/8,

    parameter int unsigned WEIGHT_STAGGER_BITWIDTH = WEIGHT_STAGGER > 1 ? $clog2(WEIGHT_STAGGER) : 1,

    parameter int unsigned NUMBANKS = N_O/PIPELINEDEPTH,
    parameter int unsigned NUM_LAYERS = 8

    )
   (
    input logic                                     clk_i,
    input logic                                     rst_ni,

    // Memory interface

    input logic [0:NUMBANKS-1]                      rw_collision_i,
    input logic [0:NUMBANKS-1]                      valid_i, // Activation memory outputs are valid

    // OCU interface

    input logic [0:NUMBANKS-1]                      ready_i, // OCU is ready for inputs

    // Layer interface

    input logic                                     latch_new_layer_i,
    input logic unsigned [$clog2(K):0]              layer_k_i,
    input logic unsigned [$clog2(N_I):0]            layer_ni_i,
    input logic unsigned [$clog2(N_O):0]            layer_no_i,

    // Control / Steering interface

    input logic                                     soft_reset_i, // Used to reset the address counters. Useful if some layer stack is to be run on multiple tiles of an image
    input logic                                     toggle_banks_i, // Switches the active weight latch bank on the OCUs once they are loaded

    output logic                                    mem_read_enable_o,
    output logic [$clog2(BANKDEPTH)-1:0]            mem_read_addr_o,
    output logic                                    weights_read_bank_o,
    output logic                                    weights_save_bank_o,
    output logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] weights_save_enable_o,
    output logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] weights_test_enable_o,
    output logic [0:WEIGHT_STAGGER-1]               weights_flush_o,
    output logic                                    ready_o, // Ready to
    output logic                                    valid_o
    );

   ///////////////////////////////// COMBINATORIAL SIGNAL /////////////////////////////////

   logic                                            mem_read_enable;
   logic                                            save_enable;
   logic unsigned [WEIGHT_STAGGER_BITWIDTH:0]       max_write_depth;

   ///////////////////////////////// END COMBINATORIAL SIGNAL /////////////////////////////////

   ///////////////////////////////// SEQUENTIAL SIGNAL /////////////////////////////////

   logic                                            init_q, init_d; // Module initialization state
   logic unsigned [$clog2(K):0]                     layer_k_q;
   logic unsigned [$clog2(N_I):0]                   layer_ni_q;
   logic unsigned [$clog2(N_O):0]                   layer_no_q;

   logic                                            weights_loaded_q, weights_loaded_d;
   logic                                            read_valid_q, read_valid_d;

   logic [$clog2(BANKDEPTH)-1:0]                    current_read_address_q, current_read_address_d;
   logic [$clog2(BANKDEPTH)-1:0]                    current_read_start_address_q, current_read_start_address_d;
   logic [$clog2(K*K)-1:0]                          current_kernel_pixel_q, current_kernel_pixel_d;
   logic [WEIGHT_STAGGER_BITWIDTH-1:0]              current_write_depth_q, current_write_depth_d;
   logic                                            current_save_bank_q, current_save_bank_d;
   logic                                            toggle_banks_q,  toggle_banks_d;
   logic                                            ready_q, ready_d;

   logic                                            one_loaded_d, one_loaded_q; // This signal is used to make sure always at least one word is loaded

   ///////////////////////////////// END SEQUENTIAL SIGNAL /////////////////////////////////

   // Number of words per kernel pixel
   assign max_write_depth = (layer_ni_q/(N_I/WEIGHT_STAGGER));

   always_comb begin
      weights_flush_o = '0;

      weights_loaded_d = weights_loaded_q;
      current_save_bank_d = current_save_bank_q;
      read_valid_d = read_valid_q;
      save_enable = 0;
      mem_read_enable = 0;
      init_d = init_q;
      ready_d = ready_q;
      one_loaded_d = one_loaded_q;

      current_kernel_pixel_d = current_kernel_pixel_q;
      current_write_depth_d = current_write_depth_q;
      current_read_address_d = current_read_address_q;
      current_read_start_address_d = current_read_start_address_q;

      // Save toggle bank signal until able to toggle
      if(toggle_banks_i == 1) begin
         toggle_banks_d = 1;
      end else begin
         toggle_banks_d = toggle_banks_q;
      end

      if(latch_new_layer_i == 1) begin
         for(int i=0;i<WEIGHT_STAGGER;i++) begin
            // Flush deeper channels if layer has fewer channels
            if(max_write_depth>i) begin
               weights_flush_o[WEIGHT_STAGGER-1-i] = 1;
            end
            // Flush all weight if sub-K size layer is loaded
            if(layer_k_i < K) begin
               weights_flush_o = '1;
            end
         end

         current_read_start_address_d = current_read_start_address_q + (K*K*WEIGHT_STAGGER);
         current_read_address_d = current_read_start_address_d;
         // current_read_address_d = (current_read_address_q / (K*K*WEIGHT_STAGGER)) * (K*K*WEIGHT_STAGGER) + (K*K*WEIGHT_STAGGER);

         ready_d = 0;
      end else if (init_q == 1) begin
         // Read order is: 0:(n_i/weight_stagger) pixels of first pixel, second pixel ... last pixel
         // Then i*(n_i/weight_stagger):(i+1)*(n_i/weight_stagger) pixels of first pixel, second pixel ... last pixel
         current_kernel_pixel_d = (current_kernel_pixel_q + 1)%(layer_k_q*layer_k_q);
         if(current_kernel_pixel_d == 0) begin
            current_write_depth_d = (current_write_depth_q + 1)%max_write_depth;
            if(current_write_depth_d == 0 && one_loaded_q == 1) begin
               weights_loaded_d = 1;
            end
         end else begin
            current_write_depth_d = current_write_depth_q;
         end

         if(toggle_banks_q == 1) begin
            if(weights_loaded_q == 1) begin
               current_save_bank_d = (current_save_bank_q+1)%2;
               weights_loaded_d = 0;
               read_valid_d = 1;
               toggle_banks_d = 0;
               init_d = 0;
               ready_d = 1;
            end else begin
               toggle_banks_d = 1;
               read_valid_d = 0;
               ready_d = 0;
            end
         end // if (toggle_bank_q == 1)

         if(rw_collision_i == '0 && valid_i == '1) begin
            save_enable = 1;
         end else begin
            save_enable = 0;
         end

         if(ready_i == '1) begin
            // Read iff initialized and not all weights are loaded
            mem_read_enable = ~weights_loaded_d & init_d;
         end else begin
            mem_read_enable = 0;
         end

         current_read_address_d = current_read_address_q + mem_read_enable;

         if(mem_read_enable == 1) begin
            one_loaded_d = 1;
         end

      end // if (init_q == 1)

      mem_read_enable_o = mem_read_enable;
      mem_read_addr_o = current_read_address_q;
      weights_read_bank_o = ~current_save_bank_q;
      weights_save_bank_o = current_save_bank_q;
      ready_o = ready_q;
      valid_o = (read_valid_q & ~latch_new_layer_i);

      weights_save_enable_o = '0;
      weights_test_enable_o = '0;

      if(save_enable) begin
         for(int i=0;i<WEIGHT_STAGGER;i++) begin
            for(int j=0;j<K;j++) begin
               for(int m=0;m<K;m++) begin

                  // Save pixel at the corrected position.
                  // For size-K kernels, just go pixel by pixel.
                  // For lower sized kernels, save around the center like this:
                  //  _ _ _ _ _
                  // |_|_|_|_|_|
                  // |_|x|x|x|_|
                  // |_|x|x|x|_|
                  // |_|x|x|x|_|
                  // |_|_|_|_|_|

                  if(i == current_write_depth_q && (j*K + m) == ((K-layer_k_q)/2)*(K+1+current_kernel_pixel_q/layer_k_q)+current_kernel_pixel_q) begin
                     weights_save_enable_o[i][j][m] = 1;
                  end
               end
            end
         end
      end // if (save_enable)

      if (soft_reset_i || latch_new_layer_i || ~init_q) begin
         init_d = init_q;
         if (latch_new_layer_i) begin
            init_d = 1;
         end
      end

      if (soft_reset_i || latch_new_layer_i || ~init_q) begin
         current_save_bank_d = current_save_bank_q;
      end

      if (soft_reset_i == 1) begin
         current_read_start_address_d = '0;
      end

      if (soft_reset_i == 1) begin
         weights_loaded_d = '0;
      end else if (latch_new_layer_i == 1) begin
         weights_loaded_d = '0;
      end else if (~init_q) begin
         weights_loaded_d = weights_loaded_q;
      end

      if (soft_reset_i == 1) begin
         current_read_address_d = '0;
      end else if (latch_new_layer_i == 1) begin
         current_read_address_d = current_read_address_q;
      end else if (~init_q) begin
         current_read_address_d = current_read_address_q;
      end

      if (soft_reset_i) begin
         toggle_banks_d = toggle_banks_q;
         ready_d = ready_q;
      end

      if (soft_reset_i || latch_new_layer_i) begin
         one_loaded_d = '0;
         read_valid_d = '0;
      end else if (~init_q) begin
         one_loaded_d = one_loaded_q;
         read_valid_d = read_valid_q;
      end

      if (soft_reset_i || latch_new_layer_i) begin
         current_kernel_pixel_d = '0;
         current_write_depth_d = '0;
      end else if (~(init_q && save_enable && ~weights_loaded_q)) begin
         current_kernel_pixel_d = current_kernel_pixel_q;
         current_write_depth_d = current_write_depth_q;
      end

   end


   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         init_q <= '0;
         layer_k_q <= K;
         layer_ni_q <= N_I;
         layer_no_q <= N_O;
         weights_loaded_q <= '0;
         read_valid_q <= '0;
         current_read_address_q <= '0;
         current_kernel_pixel_q <= '0;
         current_write_depth_q <= '0;
         current_save_bank_q <= '0;
         toggle_banks_q <= '0;
         ready_q <= '1;
         one_loaded_q <= '0;
         current_read_start_address_q <= '0;
      end else begin // if (~rst_ni)

         current_kernel_pixel_q <= current_kernel_pixel_d;
         current_write_depth_q <= current_write_depth_d;
         one_loaded_q <= one_loaded_d;
         read_valid_q <= read_valid_d;
         toggle_banks_q <= toggle_banks_d;
         ready_q <= ready_d;
         current_read_address_q <= current_read_address_d;
         weights_loaded_q <= weights_loaded_d;
         current_read_start_address_q <= current_read_start_address_d;
         current_save_bank_q <= current_save_bank_d;
         init_q <= init_d;
         if(latch_new_layer_i == 1) begin
            layer_ni_q <= layer_ni_i;
            layer_no_q <= layer_no_i;
            layer_k_q <= layer_k_i;
         end
      end
   end

endmodule
