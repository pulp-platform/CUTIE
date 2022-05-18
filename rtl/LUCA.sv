// ----------------------------------------------------------------------
//
// File: LUCA.sv
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
// Local Uppermost Control Arbiter
// This module coordinates the switching of layers, i.e. setting the right parameters in
// all lower controllers, switching weightbanks, switching memory banksets.

module LUCA
  #(
    parameter int unsigned K = 3,
    parameter int unsigned N_I = 128,
    parameter int unsigned N_O = 128,
    parameter int unsigned LAYER_FIFODEPTH = 10,
    parameter int unsigned IMAGEWIDTH = 224,
    parameter int unsigned IMAGEHEIGHT = 224,
    parameter int unsigned TCN_WIDTH = 48,
    parameter int unsigned NUMACTMEMBANKSETS = 3,
    parameter int unsigned NUMBANKS = 6,

    parameter int unsigned PIPELINEDEPTH = 2,
    parameter int unsigned OCUDELAY = 1,
    parameter int unsigned COMPUTEDELAY = PIPELINEDEPTH - 1 + OCUDELAY,
    parameter int unsigned WRITEBACKDELAY = COMPUTEDELAY + 1,
    parameter int unsigned KBITWIDTH = $clog2(K),
    parameter int unsigned NIBITWIDTH = $clog2(N_I),
    parameter int unsigned NOBITWIDTH = $clog2(N_O),

    parameter int unsigned THRESHBITWIDTH = $clog2(K*K*N_I)

    )
   (

    input logic                                  clk_i,
    input logic                                  rst_ni,

    input logic                                  store_to_fifo_i,
    input logic                                  testmode_i,

    input logic unsigned [$clog2(IMAGEWIDTH):0]  layer_imagewidth_i,
    input logic unsigned [$clog2(IMAGEHEIGHT):0] layer_imageheight_i,
    input logic unsigned [KBITWIDTH:0]           layer_k_i,
    input logic unsigned [NIBITWIDTH:0]          layer_ni_i,
    input logic unsigned [NOBITWIDTH:0]          layer_no_i,
    input logic unsigned [KBITWIDTH-1:0]         layer_stride_width_i,
    input logic unsigned [KBITWIDTH-1:0]         layer_stride_height_i,
    input logic                                  layer_padding_type_i,

    input logic                                  layer_pooling_enable_i,
    input logic                                  layer_pooling_pooling_type_i,
    input logic unsigned [KBITWIDTH-1:0]         layer_pooling_kernel_i,
    input logic                                  layer_pooling_padding_type_i,

    input logic                                  layer_skip_in_i,
    input logic                                  layer_skip_out_i,

    input logic                                  layer_is_tcn_i,
    input logic [$clog2(TCN_WIDTH)-1:0]          layer_tcn_width_i,
    input logic [$clog2(TCN_WIDTH)-1:0]          layer_tcn_width_mod_dil_i,
    input logic [$clog2(K)-1:0]                  layer_tcn_k_i,

    input logic                                  compute_disable_i,
    input logic                                  tilebuffer_done_i,
    input logic [0:PIPELINEDEPTH-1]              weightload_done_i,

    output logic                                 testmode_o,
    output logic                                 compute_latch_new_layer_o,
    output logic                                 compute_soft_reset_o,
    output logic [$clog2(IMAGEWIDTH):0]          compute_imagewidth_o,
    output logic [$clog2(IMAGEHEIGHT):0]         compute_imageheight_o,
    output logic [KBITWIDTH:0]                   compute_k_o,
    output logic [NIBITWIDTH:0]                  compute_ni_o,
    output logic [NOBITWIDTH:0]                  compute_no_o,
    output logic [KBITWIDTH-1:0]                 stride_width_o,
    output logic [KBITWIDTH-1:0]                 stride_height_o,
    output logic                                 padding_type_o,
    output logic                                 compute_is_tcn_o,
    output logic [$clog2(TCN_WIDTH)-1:0]         compute_tcn_width_o,
    output logic [$clog2(TCN_WIDTH)-1:0]         compute_tcn_width_mod_dil_o,
    output logic [$clog2(K)-1:0]                 compute_tcn_k_o,

    output logic                                 pooling_enable_o,
    output logic                                 pooling_pooling_type_o,
    output logic [KBITWIDTH-1:0]                 pooling_kernel_o,
    output logic                                 pooling_padding_type_o,

    output logic                                 skip_in_o,
    output logic                                 skip_out_o,

    output logic [$clog2(NUMACTMEMBANKSETS)-1:0] readbank_o,
    output logic [$clog2(NUMACTMEMBANKSETS)-1:0] writebank_o,
    output logic [$clog2(PIPELINEDEPTH):0]       pixelwidth_o,
    output logic                                 tcn_actmem_set_shift_o,
    output logic [$clog2(TCN_WIDTH)-1:0]         tcn_actmem_read_shift_o,
    output logic [$clog2(TCN_WIDTH)-1:0]         tcn_actmem_write_shift_o,
    output logic [0:PIPELINEDEPTH-1]             weights_latch_new_layer_o,
    output logic [KBITWIDTH:0]                   weights_k_o,
    output logic [NIBITWIDTH:0]                  weights_ni_o,
    output logic [NOBITWIDTH:0]                  weights_no_o,
    output logic [0:PIPELINEDEPTH-1]             weights_soft_reset_o,
    output logic [0:PIPELINEDEPTH-1]             weights_toggle_banks_o,
    output logic                                 fifo_pop_o,
    output logic                                 compute_done_o
    );

   typedef struct                                packed{
      logic [$clog2(IMAGEWIDTH):0]               imagewidth;
      logic [$clog2(IMAGEHEIGHT):0]              imageheight;
      logic unsigned [KBITWIDTH:0]               k;
      logic unsigned [NIBITWIDTH:0]              ni;
      logic unsigned [NOBITWIDTH:0]              no;
      logic unsigned [KBITWIDTH-1:0]             stride_width;
      logic unsigned [KBITWIDTH-1:0]             stride_height;
      logic                                      padding_type;
      logic                                      pooling_enable;
      logic                                      pooling_pooling_type;
      logic [KBITWIDTH-1:0]                      pooling_kernel;
      logic                                      pooling_padding_type;
      logic                                      skip_in;
      logic                                      skip_out;
      logic                                      is_tcn;
      logic [$clog2(TCN_WIDTH)-1:0]              tcn_width;
      logic [$clog2(TCN_WIDTH)-1:0]              tcn_width_mod_dil;
      logic [$clog2(K)-1:0]                      tcn_k;
   } layer_t;

   layer_t next_layer, current_layer, current_layer_d, input_layer;

   logic                                         current_layer_done_q, current_layer_done_d;
   logic [$clog2(NUMACTMEMBANKSETS)-1:0]         readbank_q, readbank_d;
   logic [$clog2(NUMACTMEMBANKSETS)-1:0]         writebank_q, writebank_d;


   // The timer is used to time the writeback of the last valid computation
   logic                                         timer_started_q, timer_started_d;
   logic [$clog2(PIPELINEDEPTH+2)-1:0]           timer_q, timer_d;

   logic [PIPELINEDEPTH-1:0]                     max_pipelinedepth_weights, max_pipelinedepth_compute;

   logic                                         layer_fifo_empty, layer_fifo_flush;
   logic [$clog2(LAYER_FIFODEPTH):0]             layer_fifo_usage;
   logic                                         layer_fifo_full;

   logic [$clog2(LAYER_FIFODEPTH):0]             num_layers_q, num_layers_d;
   logic [$clog2(LAYER_FIFODEPTH):0]             num_cnn_layers_q, num_cnn_layers_d;
   logic [$clog2(LAYER_FIFODEPTH):0]             num_tcn_layers_q, num_tcn_layers_d;
   logic [$clog2(LAYER_FIFODEPTH):0]             compute_layer_running_q, compute_layer_running_d;
   logic [$clog2(LAYER_FIFODEPTH):0]             weight_layer_running_q, weight_layer_running_d;
   logic                                         iteration_done_q, iteration_done_d;
   logic [$clog2(NUMBANKS)-1:0]                  tcn_actmem_read_shift_q, tcn_actmem_read_shift_d;
   logic [$clog2(NUMBANKS)-1:0]                  tcn_actmem_write_shift_q, tcn_actmem_write_shift_d;
   logic [$clog2(TCN_WIDTH)-1:0]                 tcn_width_q, tcn_width_d;

   logic                                         weightload_ready_q, weightload_ready_d;
   logic                                         fifo_popped_q;
   logic                                         fifo_push;

   logic [$bits(layer_t)-1:0]                    fifo_input, fifo_output;


   assign layer_fifo_flush = 0;
   assign testmode_o = testmode_i;
   assign readbank_o = readbank_d;
   assign writebank_o = writebank_d;

   assign fifo_input = (store_to_fifo_i) ? {>>{input_layer}} : fifo_output;
   assign next_layer = {>>{fifo_output}};
   assign fifo_push = store_to_fifo_i || fifo_pop_o;

   fifo_v3 #( .FALL_THROUGH('0),
              .DATA_WIDTH($bits(layer_t)),
              .DEPTH(LAYER_FIFODEPTH+1)
              ) layer_fifo (
                            .clk_i(clk_i),
                            .rst_ni(rst_ni),
                            .flush_i(layer_fifo_flush),
                            .testmode_i('0),
                            .full_o(layer_fifo_full),
                            .empty_o(layer_fifo_empty),
                            .usage_o(layer_fifo_usage),
                            .data_i(fifo_input),
                            .push_i(fifo_push),
                            .data_o(fifo_output),
                            .pop_i(fifo_pop_o)
                            );


   always_comb begin

      input_layer.k = layer_k_i;
      input_layer.ni = layer_ni_i;
      input_layer.no = layer_no_i;
      input_layer.imagewidth = layer_imagewidth_i;
      input_layer.imageheight = layer_imageheight_i;
      input_layer.stride_width = layer_stride_width_i;
      input_layer.stride_height = layer_stride_height_i;
      input_layer.padding_type = layer_padding_type_i;
      input_layer.pooling_enable = layer_pooling_enable_i;
      input_layer.pooling_pooling_type = layer_pooling_pooling_type_i;
      input_layer.pooling_padding_type = layer_pooling_padding_type_i;
      input_layer.pooling_kernel = layer_pooling_kernel_i;
      input_layer.skip_in = layer_skip_in_i;
      input_layer.skip_out = layer_skip_out_i;
      input_layer.is_tcn = layer_is_tcn_i;
      input_layer.tcn_width = layer_tcn_width_i;
      input_layer.tcn_width_mod_dil = layer_tcn_width_mod_dil_i;
      input_layer.tcn_k = layer_tcn_k_i;

      compute_latch_new_layer_o = 0;

      compute_k_o = current_layer.k;
      compute_ni_o = current_layer.ni;
      compute_no_o = current_layer.no;
      compute_imagewidth_o = current_layer.imagewidth;
      compute_imageheight_o = current_layer.imageheight;
      stride_width_o = current_layer.stride_width;
      stride_height_o = current_layer.stride_height;
      padding_type_o = current_layer.padding_type;

      pooling_enable_o = current_layer.pooling_enable;
      pooling_pooling_type_o = current_layer.pooling_pooling_type;
      pooling_padding_type_o = current_layer.pooling_padding_type;
      pooling_kernel_o = current_layer.pooling_kernel;

      skip_in_o = current_layer.skip_in;
      skip_out_o = current_layer.skip_out;

      compute_is_tcn_o = current_layer.is_tcn;
      compute_tcn_width_o = current_layer.tcn_width;
      compute_tcn_width_mod_dil_o = current_layer.tcn_width_mod_dil;
      compute_tcn_k_o = current_layer.tcn_k;

      pixelwidth_o = '0;
      tcn_actmem_set_shift_o = '0;
      tcn_actmem_read_shift_o = '0;
      tcn_actmem_write_shift_o = '0;

      readbank_d = readbank_q;
      writebank_d = writebank_q;

      weights_latch_new_layer_o = '0;
      weights_k_o = next_layer.k;
      weights_ni_o = next_layer.ni;
      weights_no_o = next_layer.no;

      max_pipelinedepth_weights = (weights_no_o+(N_O/PIPELINEDEPTH-1) )/ (N_O/PIPELINEDEPTH);
      max_pipelinedepth_compute = (compute_no_o+(N_O/PIPELINEDEPTH-1) )/ (N_O/PIPELINEDEPTH);
      fifo_pop_o = 0;
      compute_done_o = 0;

      num_layers_d = num_layers_q;
      num_cnn_layers_d = num_cnn_layers_q;
      num_tcn_layers_d = num_tcn_layers_q;
      tcn_width_d = tcn_width_q;

      if (store_to_fifo_i) begin
         num_layers_d = num_layers_q + 1;
         if (layer_is_tcn_i) begin
            num_tcn_layers_d = num_tcn_layers_q + 1;
            tcn_width_d = layer_tcn_width_i;
            if (num_tcn_layers_q == 0) begin
               pixelwidth_o = (input_layer.ni +  (N_I / PIPELINEDEPTH) - 1) / (N_I / PIPELINEDEPTH);
               tcn_actmem_set_shift_o = 1'b1;
               tcn_actmem_read_shift_o = TCN_WIDTH - pixelwidth_o * input_layer.tcn_width;
               tcn_actmem_write_shift_o = '0;
            end
         end else begin
            num_cnn_layers_d = num_cnn_layers_q + 1;
         end
      end

      iteration_done_d = iteration_done_q;
      compute_layer_running_d = compute_layer_running_q;
      weight_layer_running_d = weight_layer_running_q;
      weightload_ready_d = weightload_ready_q;
      weights_toggle_banks_o = '0;
      tcn_actmem_read_shift_d = tcn_actmem_read_shift_q;
      tcn_actmem_write_shift_d = tcn_actmem_write_shift_q;

      if(current_layer_done_q == 1 && compute_latch_new_layer_o == 0 && compute_layer_running_q == num_layers_q) begin
         compute_done_o = 1;
         compute_layer_running_d = 0;
         weightload_ready_d = 1;
         iteration_done_d = 1;
      end

      if (compute_disable_i == 0 && iteration_done_d == 0) begin

         if(layer_fifo_empty == 0 && current_layer_done_q == 1 && fifo_popped_q == 0) begin
            fifo_pop_o = 1;
         end
         if(fifo_popped_q == 1) begin
            compute_layer_running_d = compute_layer_running_q + 1;
            compute_latch_new_layer_o = 1;
            if (num_tcn_layers_q != 0) begin
               // Write of last CNN layer is directed at 3rd actmem set
               // Read of first TCN layer is directed at 3rd actmem set
               // Otherwise they just toggle between 1 and 2
               writebank_d = (compute_layer_running_q == num_cnn_layers_q - 1)? 2 : (compute_layer_running_q + 1) % 2;
               readbank_d = (compute_layer_running_q == num_cnn_layers_q)? 2 : compute_layer_running_q % 2;
               if (compute_layer_running_q == num_cnn_layers_q - 1) begin

                  tcn_actmem_write_shift_d = (tcn_actmem_write_shift_q + 1 == NUMBANKS)? '0 : tcn_actmem_write_shift_q + 1;
                  tcn_actmem_read_shift_d = (tcn_actmem_write_shift_d + 1 + NUMBANKS - tcn_width_q) % NUMBANKS;
               end

            end else begin
               readbank_d = compute_layer_running_q % 2;
               writebank_d = (compute_layer_running_q + 1) % 2;
            end
            for(int i=0;i<PIPELINEDEPTH;i++) begin
               if(i<max_pipelinedepth_compute) begin
                  weights_toggle_banks_o[i] = 1;
               end
            end
         end
         if(weightload_done_i[0] == 1 && weightload_ready_q == 1 && layer_fifo_empty == 0) begin
            if(weight_layer_running_q < num_layers_q) begin
               weight_layer_running_d = weight_layer_running_q + 1;
               for(int i=0;i<PIPELINEDEPTH;i++) begin
                  if(i<max_pipelinedepth_weights) begin
                     weights_latch_new_layer_o[i] = 1;
                  end
               end
            end else begin
               weight_layer_running_d = 0;
            end
            weightload_ready_d = 0;
         end
      end //if (compute_disable_i == 0)

      // Once an iteration is finished, increment TCN Ringbuffer shifts by one
      // if(iteration_done_d && !iteration_done_q) begin
      //    tcn_actmem_write_shift_d = (tcn_actmem_write_shift_q + 1 == NUMBANKS)? '0 : tcn_actmem_write_shift_q + 1;
      //    tcn_actmem_read_shift_d = (tcn_actmem_write_shift_d + NUMBANKS - tcn_width_q) % NUMBANKS;
      // end

      if(fifo_pop_o == 1) begin
         weightload_ready_d = 1;
      end

      weights_soft_reset_o = {2{weights_latch_new_layer_o && (weight_layer_running_q == 0)}};
      compute_soft_reset_o = compute_latch_new_layer_o && (compute_layer_running_q == 0);

      // weights_soft_reset_o = 0;
   end // always_comb

   always_comb begin
      timer_started_d = timer_started_q;
      timer_d = timer_q;

      if(tilebuffer_done_i == 1 && weightload_done_i[0] == 1 && timer_started_q == 0 && compute_layer_running_q > 0) begin
         timer_started_d = 1;
      end else if(timer_started_q == 1) begin
         timer_d = (timer_q+1)%(WRITEBACKDELAY);
         if(timer_d == '0) begin
            timer_started_d = 0;
         end
      end

      if (timer_started_q == 1 && compute_latch_new_layer_o == 0) begin
         if(timer_d == '0) begin
            timer_started_d = 0;
         end
      end else if(compute_latch_new_layer_o == 1) begin
         timer_started_d = 0;
         timer_d = '0;
      end

   end

   always_comb begin

      if(compute_latch_new_layer_o == 0 && weightload_ready_q == 0 && tilebuffer_done_i == 1) begin
         current_layer_done_d = 1;
      end

      if (timer_started_q == 1 && compute_latch_new_layer_o == 0) begin
         if(timer_d == '0) begin
            current_layer_done_d = 1;
         end
      end else if(compute_latch_new_layer_o == 1) begin
         current_layer_done_d = 0;
      end
   end // always_comb

   always_comb begin
      if(fifo_pop_o == 1 && layer_fifo_empty == 0) begin
         current_layer_d = next_layer;
      end else begin
         current_layer_d = current_layer;
      end
   end

   always_ff @(posedge clk_i, negedge rst_ni) begin

      if(~rst_ni)begin
         timer_q <= '0;
         timer_started_q <= '0;
         current_layer_done_q <= 0;
         readbank_q <= 1;
         writebank_q <= 0;
         compute_layer_running_q <= '0;
         weight_layer_running_q <= '0;
         fifo_popped_q <= '0;
         weightload_ready_q <= 1;
         current_layer <= '0;
         num_layers_q <= '0;
         num_cnn_layers_q <= '0;
         num_tcn_layers_q <= '0;
         iteration_done_q <= 1;
         tcn_actmem_write_shift_q <= NUMBANKS-1;
         tcn_actmem_read_shift_q <= '0;
         tcn_width_q <= '0;
      end else begin // if (~rst_ni)

         readbank_q <= readbank_d;
         writebank_q <= writebank_d;
         fifo_popped_q <= fifo_pop_o;
         weightload_ready_q <= weightload_ready_d;
         num_layers_q <= num_layers_d;
         num_cnn_layers_q <= num_cnn_layers_d;
         num_tcn_layers_q <= num_tcn_layers_d;
         compute_layer_running_q <= compute_layer_running_d;
         weight_layer_running_q <= weight_layer_running_d;
         iteration_done_q <= (compute_disable_i)? 0: iteration_done_d;
         tcn_actmem_write_shift_q <= tcn_actmem_write_shift_d;
         tcn_actmem_read_shift_q <= tcn_actmem_read_shift_d;
         tcn_width_q <= tcn_width_d;
         current_layer_done_q <= current_layer_done_d;
         current_layer <= current_layer_d;
         timer_q <= timer_d;
         timer_started_q <= timer_started_d;

      end // else: !if(~rst_ni)
   end // always_ff @ (posedge clk_i, negedge rst_ni)

endmodule
