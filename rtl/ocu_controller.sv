// ----------------------------------------------------------------------
//
// File: ocu_controller.sv
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

// The OCU controller modules manages the loading of the threshold values for all OCUs,
// manages their pooling behaviour and enables/disables their computing

// TODO: Implement support for Pooling

module ocu_controller
  #(
    parameter int unsigned N_O = 512,
    parameter int unsigned PIPELINEDEPTH = 2,
    parameter int unsigned IMAGEWIDTH = 32,
    parameter int unsigned IMAGEHEIGHT = 32,
    parameter int unsigned K = 3
    )
   (
    input logic                         clk_i,
    input logic                         rst_ni,

    input logic                         latch_new_layer_i,
    input logic [$clog2(N_O):0]         layer_no_i,

    input logic [$clog2(IMAGEWIDTH):0]  layer_imagewidth_i,
    input logic [$clog2(IMAGEHEIGHT):0] layer_imageheight_i,

    input logic                         layer_pooling_enable_i,
    input logic                         layer_pooling_pooling_type_i,
    input logic [$clog2(K)-1:0]         layer_pooling_kernel_i,
    input logic                         layer_pooling_padding_type_i,

    input logic                         layer_skip_in_i,
    input logic                         layer_skip_out_i,

    input logic                         tilebuffer_valid_i,
    input logic [0:N_O-1]               weightmemory_valid_i,

    output logic [0:PIPELINEDEPTH-1]    compute_enable_o,
    output logic                        pooling_fifo_flush_o,
    output logic                        pooling_fifo_testmode_o,
    output logic                        pooling_store_to_fifo_o, // 1: Store, 0: Don't store PIPELINE

    output logic                        threshold_fifo_flush_o,
    output logic                        threshold_fifo_testmode_o,
    output logic [0:N_O-1]              threshold_pop_o, // 1: Store, 0: Don't store

    output                              enums_ocu_pool::alu_operand_sel alu_operand_sel_o, // 01: FIFO, 10: previous result, 00: zero ATTENTION: Choosing 01 also pops from FIFO! PIPELINE
    output                              enums_ocu_pool::multiplexer multiplexer_o, // 1: Use ALU result, 0: Use current convolution result
    output                              enums_ocu_pool::alu_op alu_op_o, // 1: Sum, 0: Max

    output logic                        ready_o,
    output logic                        valid_o
    );

   import enums_ocu_pool::*;

   logic [0:PIPELINEDEPTH-1]            compute_enable_out, compute_enable;

   logic                                init_q;
   logic [$clog2(N_O):0]                layer_no_q;
   logic [$clog2(IMAGEWIDTH):0]         layer_imagewidth_q;
   logic [$clog2(IMAGEHEIGHT):0]        layer_imageheight_q;
   logic                                layer_pooling_enable_q;
   logic                                layer_pooling_pooling_type_q;
   logic [$clog2(K)-1:0]                layer_pooling_kernel_q;
   logic                                layer_pooling_padding_type_q;

   logic                                layer_skip_in_q;
   logic                                layer_skip_out_q;

   logic                                next_valid, valid_q, valid_out, valid_out_q;
   logic [0:PIPELINEDEPTH-2]            tilebuffer_valid_q;
   logic [0:PIPELINEDEPTH-1]            tilebuffer_valid;

   logic [$clog2(IMAGEHEIGHT)-1:0]      pooling_line_counter_d, pooling_line_counter_q;
   logic [$clog2(IMAGEWIDTH)-1:0]       pooling_pixel_counter_d,pooling_pixel_counter_q, pooling_pixel_counter_q2;

   logic [$clog2(K)-1:0]                pooling_width_counter_d, pooling_width_counter_q;
   logic [PIPELINEDEPTH-1:0]            previous_compute_enable_q;

   logic                                pooling_valid;
   logic                                stop;

   assign compute_enable_o = compute_enable_out;
   assign valid_o = layer_pooling_enable_q == 1 ? valid_out : compute_enable_out[0];

   //    assign valid_o = layer_pooling_enable_q == 1 ?
   //    pooling_line_counter_q % layer_pooling_kernel_q == 0 &&
   //    pooling_pixel_counter_q % layer_pooling_kernel_q == layer_pooling_kernel_q - 1 &&
   //    valid_q
   //    :
   //    compute_enable_out[0];

   always_comb begin

      ///////////////////////////////// DEFAULT SETUP /////////////////////////////////

      tilebuffer_valid[0] = tilebuffer_valid_i;
      for (int i=1;i<PIPELINEDEPTH;i++) begin
         tilebuffer_valid[i] = tilebuffer_valid_q[i-1];
      end

      compute_enable = '0;
      compute_enable_out = '0;
      valid_out = '0;
      pooling_fifo_flush_o = '0;
      pooling_fifo_testmode_o = '0;
      pooling_store_to_fifo_o = '0;
      alu_operand_sel_o = ALU_OPERAND_MINUS_INF;
      multiplexer_o = enums_ocu_pool::multiplexer'(layer_pooling_enable_q);
      alu_op_o = enums_ocu_pool::alu_op'(layer_pooling_pooling_type_q);
      ready_o = '0;
      next_valid = '0;

      pooling_valid = 0;
      pooling_width_counter_d = pooling_width_counter_q;
      pooling_line_counter_d = pooling_line_counter_q;
      pooling_pixel_counter_d = pooling_pixel_counter_q;
      stop = 0;

      threshold_pop_o = '0;
      threshold_fifo_testmode_o = '0;
      threshold_fifo_flush_o = '0;

      ///////////////////////////////// END DEFAULT SETUP /////////////////////////////////
      // Used to pop too early; Fixed now.
      if(latch_new_layer_i == 1 && init_q == 1) begin
         //      if(latch_new_layer_i == 1) begin
         for(int i=0;i<N_O;i++) begin
            if(i<layer_no_i) begin
               // Have the OCUs load the next threshold, if they are computing in the current layer
               threshold_pop_o[i] = 1;
            end
         end
      end

      if(init_q == 1 && latch_new_layer_i == 0) begin
         ready_o = '1;
         for(int i=0;i<PIPELINEDEPTH;i++) begin
            // If there is a new window coming
            if(ready_o == 1 && tilebuffer_valid[i] == 1) begin
               // Enable all compute units that are needed
               if(i<(layer_no_q+(N_O/PIPELINEDEPTH-1))/(N_O/PIPELINEDEPTH)) begin
                  compute_enable[i] = 1;
                  next_valid = 1;
               end
            end
         end
         if(tilebuffer_valid_q[0] == 1) begin
            if (layer_skip_in_q == 1 || layer_skip_out_q == 1) begin
               if(layer_skip_in_q == 1) begin
                  pooling_store_to_fifo_o = 1;
                  alu_op_o = ALU_OP_SUM;
                  alu_operand_sel_o = ALU_OPERAND_ZERO;
               end
               if(layer_skip_out_q == 1) begin
                  alu_op_o = ALU_OP_SUM;
                  alu_operand_sel_o = ALU_OPERAND_FIFO;
                  multiplexer_o = MULTIPLEXER_ALU;
               end
            end else if(layer_pooling_enable_q == 1) begin
               pooling_pixel_counter_d = (pooling_pixel_counter_q + 1)%(layer_imagewidth_q);
               if(pooling_pixel_counter_d == 0) begin
                  pooling_line_counter_d = (pooling_line_counter_q +1);
               end
               if(pooling_pixel_counter_q < layer_imageheight_q - (layer_imageheight_q%layer_pooling_kernel_q) || layer_imagewidth_q%layer_pooling_kernel_q==0) begin
                  pooling_width_counter_d = (pooling_width_counter_q + 1)%(layer_pooling_kernel_q);
               end else if (pooling_pixel_counter_q >= layer_imageheight_q - (layer_imageheight_q%layer_pooling_kernel_q) && layer_pooling_padding_type_q == 1) begin
                  pooling_width_counter_d = (pooling_width_counter_q + 1)%(layer_imagewidth_q%layer_pooling_kernel_q);
               end else begin
                  pooling_width_counter_d = 0;
                  stop = 1;
               end
               if (pooling_width_counter_q == 0 && stop == 0) begin
                  if (pooling_line_counter_q%layer_pooling_kernel_q==1) begin
                     if (layer_pooling_pooling_type_q == 1) begin
                        alu_operand_sel_o = ALU_OPERAND_ZERO; // ZERO
                     end else begin
                        alu_operand_sel_o = ALU_OPERAND_MINUS_INF; // -INF
                     end
                  end else begin
                     alu_operand_sel_o = ALU_OPERAND_FIFO; // FIFO
                  end

                  if (pooling_line_counter_q <= layer_imageheight_q - (layer_imageheight_q%layer_pooling_kernel_q) || layer_imageheight_q % layer_pooling_kernel_q == 0) begin
                     if ((pooling_line_counter_q)%(layer_pooling_kernel_q) == 0) begin
                        pooling_valid = 1;
                     end
                  end else if (layer_pooling_padding_type_q == 1) begin
                     if (pooling_line_counter_q%(layer_imageheight_q%layer_pooling_kernel_q) == 0) begin
                        pooling_valid = 1;
                     end
                  end else begin
                     pooling_valid = 0;
                  end

               end else begin // if ()
                  if (layer_imagewidth_q%layer_pooling_kernel_q != 0 && layer_pooling_padding_type_q == 1 && pooling_line_counter_q%layer_pooling_kernel_q!=1 && pooling_pixel_counter_q == 0) begin
                     alu_operand_sel_o = ALU_OPERAND_FIFO; // FIFO
                     pooling_valid = 1;
                  end else begin
                     alu_operand_sel_o = ALU_OPERAND_PREVIOUS; // PREVIOUS
                  end
               end
               if (pooling_width_counter_d == 0 && pooling_line_counter_q%layer_pooling_kernel_q>0 && pooling_line_counter_q < layer_imageheight_q && stop == 0) begin
                  pooling_store_to_fifo_o = 1;
               end else if (pooling_pixel_counter_q2 == layer_imagewidth_q && pooling_line_counter_q%layer_pooling_kernel_q>0 && pooling_pixel_counter_q == 0 && layer_pooling_padding_type_q == 1 && layer_imagewidth_q%layer_pooling_kernel_q != 0)  begin
                  pooling_store_to_fifo_o = 1;
               end

            end
         end


         compute_enable_out = compute_enable;
         if(layer_pooling_enable_q == 1) begin
            for(int i=0;i<PIPELINEDEPTH;i++) begin
               compute_enable_out[i] = ((compute_enable[i] | previous_compute_enable_q[PIPELINEDEPTH-i-1]));
            end
         end

         if (layer_pooling_enable_q == 1) begin
            if (valid_q == 1 && pooling_valid == 1) begin
               valid_out = 1;
            end else begin
               valid_out = 0;
            end
         end else begin
            if(layer_skip_in_q == 1 && layer_skip_out_q == 0)begin
               valid_out = 0;
            end else begin
               valid_out = valid_q;
            end
         end // else: !if(layer_pooling_enable_q == 1)

      end
   end

   always_ff @(posedge clk_i, negedge rst_ni) begin
      if(~rst_ni) begin
         pooling_line_counter_q <= 1;
         pooling_pixel_counter_q <= '0;
         pooling_pixel_counter_q2 <= '0;
         pooling_width_counter_q <= '0;
         previous_compute_enable_q <= '0;

         valid_q <= '0;
         valid_out_q <= '0;
         tilebuffer_valid_q <= '0;

         init_q <= '0;
         layer_no_q <= N_O;
         layer_imagewidth_q <= IMAGEWIDTH;
         layer_imageheight_q <= IMAGEHEIGHT;
         layer_pooling_enable_q <= '0;
         layer_pooling_pooling_type_q <= '0;
         layer_pooling_padding_type_q <= '0;
         layer_pooling_kernel_q <= K;

         layer_skip_in_q <= 0;
         layer_skip_out_q <= 0;

      end else begin // if (~rst_ni)
         valid_out_q <= valid_out;
         valid_q <= next_valid;
         tilebuffer_valid_q <= tilebuffer_valid[0];

         if(latch_new_layer_i) begin

            pooling_line_counter_q <= 1;
            pooling_pixel_counter_q <= '0;
            pooling_pixel_counter_q2 <= '0;
            pooling_width_counter_q <= '0;
            previous_compute_enable_q <= '0;

            layer_no_q <= layer_no_i;
            layer_imagewidth_q <= layer_imagewidth_i;
            layer_imageheight_q <= layer_imageheight_i;
            layer_pooling_enable_q <= layer_pooling_enable_i;
            layer_pooling_pooling_type_q <= layer_pooling_pooling_type_i;
            layer_pooling_padding_type_q <= layer_pooling_padding_type_i;
            layer_pooling_kernel_q <= layer_pooling_kernel_i;

            layer_skip_in_q <= layer_skip_in_i;
            layer_skip_out_q <= layer_skip_out_i;

            init_q <= 1;
         end else begin // if (latch_new_layer_i == 1)
            pooling_line_counter_q <= pooling_line_counter_d;
            pooling_pixel_counter_q2 <= pooling_pixel_counter_q;
            pooling_pixel_counter_q <= pooling_pixel_counter_d;
            pooling_width_counter_q <= pooling_width_counter_d;
            previous_compute_enable_q <= compute_enable;

         end
      end

   end


endmodule // out_channel_compute_unit
