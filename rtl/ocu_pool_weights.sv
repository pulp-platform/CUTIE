// ----------------------------------------------------------------------
//
// File: ocu_pool_weights.sv
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

// This module is the compute core of the system. It multiplies a kernel with pre-stored weights.
// ocu_pool_weights only delas with the combinatorial parts of the OCU. The weight buffering modules
// are to be found in weightbufferblock(_latch).sv.

// The module is parametrized with N_I, K, FIFODEPTH and WEIGHT_STAGGER.
// N_I dictates the number of kernel channels
// K dictates the size of the SQUARE! kernel.
// POOLING_FIFODEPTH dictates the size of the Pooling FIFO
// THRESHOLD_FIFODEPTH dictates the size of the Threshold FIFO
// WEIGHT_STAGGER dictates the number of cycles it takes to load a full set of kernel weights.

module ocu_pool_weights
  import enums_ocu_pool::*;
   #(
     parameter int unsigned N_I = 512,
     parameter int unsigned K = 3,
     parameter int unsigned POOLING_FIFODEPTH = 32,
     parameter int unsigned THRESHOLD_FIFODEPTH = 2,
     parameter int unsigned WEIGHT_STAGGER = 8,
     parameter int unsigned POOLING_USAGEWIDTH = POOLING_FIFODEPTH > 1 ? $clog2(POOLING_FIFODEPTH) : 1,
     parameter int unsigned THRESHOLD_USAGEWIDTH = THRESHOLD_FIFODEPTH > 1 ? $clog2(THRESHOLD_FIFODEPTH) : 1,
     parameter int unsigned THRESHOLD_DATAWIDTH = 2*($clog2(K*K*N_I)+1),
     parameter int unsigned FIFO_DATA_WIDTH = $clog2(K*K*N_I),

     parameter int unsigned TREEWIDTH = 1536
     )
   (
    // Data in
    input logic [0:(N_I/WEIGHT_STAGGER)-1][1:0]    weights_i,
    input logic [0:K-1][0:K-1][0:N_I-1][1:0]       acts_i ,

    // Thresholds
    input logic signed [$clog2(K*K*N_I):0]         thresh_pos_i, thresh_neg_i, // these are signed values!

    input logic                                    clk_i,
    input logic                                    rst_ni,

    // Main processing control signals
    // State transition control signal
    input logic                                    compute_enable_i,

    // Side processing control signals
    // Pooling FIFO Control signals
    input logic                                    pooling_fifo_flush_i,
    input logic                                    pooling_fifo_testmode_i,
    input logic                                    pooling_store_to_fifo_i, // 1: Store, 0: Don't store

    // Threshold FIFO Control signals
    input logic                                    threshold_fifo_flush_i,
    input logic                                    threshold_fifo_testmode_i,
    input logic                                    threshold_store_to_fifo_i, // 1: Store, 0: Don't store
    input logic                                    threshold_pop_i,
    // ALU control signals
    input                                          enums_ocu_pool::alu_operand_sel alu_operand_sel_i, // 01: FIFO, 10: previous result, 00: zero ATTENTION: Choosing 01 also pops from FIFO!
    input                                          enums_ocu_pool::multiplexer multiplexer_i, // 1: Use ALU result, 0: Use current convolution result
    input                                          enums_ocu_pool::alu_op alu_op_i, // 1: Sum, 0: Max

    // Memory control signals
    input logic                                    weights_read_bank_i,
    input logic                                    weights_save_bank_i,
    input logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] weights_save_enable_i,
    input logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] weights_test_enable_i,

    input logic [0:WEIGHT_STAGGER-1]               weights_flush_i,

    // Outputs
    output logic [1:0]                             out_o,
    output logic [FIFO_DATA_WIDTH:0]               fp_out_o
    );

   localparam FIFO_FALL_THROUGH = 1'b0;
   localparam FIFO_DEPTH = POOLING_FIFODEPTH;

   ///////////////////////////////// COMBINATORIAL SIGNALS /////////////////////////////////

   logic [K*K*N_I-1:0]                             bitvec_pos, bitvec_neg;

   logic [$clog2(K*K*N_I):0]                       sum_pos, sum_neg;
   logic signed [FIFO_DATA_WIDTH-1:0]              sum_tot;

   logic                                           fifo_push, fifo_pop;
   logic signed [FIFO_DATA_WIDTH-1:0]              fifo_data_out;

   logic signed [FIFO_DATA_WIDTH-1:0]              alu_data_in_1;
   logic signed [FIFO_DATA_WIDTH-1:0]              alu_data_in_2;
   logic signed [FIFO_DATA_WIDTH-1:0]              alu_data_out;

   logic signed [$clog2(K*K*N_I):0]                threshold_input;

   logic signed [0:1][$clog2(K*K*N_I):0]           thresholds_in;
   logic signed [0:1][$clog2(K*K*N_I):0]           thresholds_out;

   logic [0:1][0:WEIGHT_STAGGER-1][0:K-1][0:K-1]   weights_save_enable, weights_test_enable;

   logic signed [$clog2(K*K*N_I):0]                thresh_pos, thresh_neg;

   logic [POOLING_USAGEWIDTH-1:0]                  pooling_fifo_usage;
   logic                                           pooling_fifo_full;
   logic                                           pooling_fifo_empty;

   logic [THRESHOLD_USAGEWIDTH:0]                  threshold_fifo_usage;
   logic                                           threshold_fifo_full;
   logic                                           threshold_fifo_empty;

   // Full view of all weights over both banks
   logic [0:1][0:WEIGHT_STAGGER-1][0:K-1][0:K-1][0:(N_I/WEIGHT_STAGGER)-1][1:0] weights_interim;

   // Rearranged view of weights of one bank
   logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1][0:(N_I/WEIGHT_STAGGER)-1][1:0]      weights_read_interim;

   // Actual weights that are multiplied
   logic [0:K-1][0:K-1][0:N_I-1][1:0]                                           weights;
   logic [0:1] [0:WEIGHT_STAGGER-1]                                             weights_flush;


   ///////////////////////////////// END COMBINATORIAL SIGNALS /////////////////////////////////

   ///////////////////////////////// SEQUENTIAL SIGNALS /////////////////////////////////

   logic signed [FIFO_DATA_WIDTH-1:0]                                           previous_alu_data_out_q;
   logic signed [FIFO_DATA_WIDTH-1:0]                                           current_sum_q;

   ///////////////////////////////// END SEQUENTIAL SIGNALS /////////////////////////////////

   always_comb begin : weightbank_arbitration

      weights_save_enable = '0;
      weights_test_enable = '0;

      if ( weights_save_bank_i == 1'b0 ) begin
         weights_save_enable[0] = weights_save_enable_i;
         weights_test_enable[0] = weights_test_enable_i;
      end else begin
         weights_save_enable[1] = weights_save_enable_i;
         weights_test_enable[1] = weights_test_enable_i;
      end

   end // block: weightbank_arbitration


   genvar                                                                       m;
   genvar                                                                       n;
   genvar                                                                       o;
   generate
      for (m=0; m<K; m++)  begin : ternary_multiplier // Generate all ternary multipliers
         for (n=0; n<K; n++)  begin // Generate all ternary multipliers
            for (o=0; o<N_I; o++)  begin // Generate all ternary multipliers
               logic [1:0] result;
               ternary_mult tern(
                                 .act_i(acts_i[m][n][o]),
                                 .weight_i(weights[m][n][o]),
                                 .outp_o(result)
                                 );
               assign bitvec_pos[m*K*N_I + n*N_I + o] = result[1];
               assign bitvec_neg[m*K*N_I + n*N_I + o] = result[0];
            end
         end // for (n=0; n<K; n++)
      end
   endgenerate

   addertree
     #(
       /* AUTOINSTPARAM */
       .N                       (K*K*N_I),
       .TREEWIDTH                       (TREEWIDTH))
   addertree_pos_i
     (
      .popc_o                           (sum_pos),
      .in_i                             (bitvec_pos)
      );


   addertree
     #(
       .N                       (K*K*N_I),
       .TREEWIDTH                       (TREEWIDTH))
   addertree_neg_i
     (
      .popc_o                           (sum_neg),
      .in_i                             (bitvec_neg)
      );


   fifo_v3
     #(.FALL_THROUGH(FIFO_FALL_THROUGH),
       .DATA_WIDTH(FIFO_DATA_WIDTH),
       .DEPTH(POOLING_FIFODEPTH)
       )
   pooling_fifo  (
                  .clk_i(clk_i),
                  .rst_ni(rst_ni),
                  .flush_i(pooling_fifo_flush_i),
                  .testmode_i(pooling_fifo_testmode_i),
                  .full_o(pooling_fifo_full),
                  .empty_o(pooling_fifo_empty),
                  .usage_o(pooling_fifo_usage),
                  .data_i(alu_data_out),
                  .push_i(fifo_push),
                  .data_o(fifo_data_out),
                  .pop_i(fifo_pop)
                  );

   fifo_v3
     #(.FALL_THROUGH(FIFO_FALL_THROUGH),
       .DATA_WIDTH(THRESHOLD_DATAWIDTH),
       .DEPTH(THRESHOLD_FIFODEPTH+1)
       )
   threshold_fifo  (
                    .clk_i(clk_i),
                    .rst_ni(rst_ni),
                    .flush_i(threshold_fifo_flush_i),
                    .testmode_i(threshold_fifo_testmode_i),
                    .full_o(threshold_fifo_full),
                    .empty_o(threshold_fifo_empty),
                    .usage_o(threshold_fifo_usage),
                    .data_i(thresholds_in),
                    .push_i(threshold_store_to_fifo_i || threshold_pop_i),
                    .data_o(thresholds_out),
                    .pop_i(threshold_pop_i)
                    );


   assign thresholds_in[0] = (threshold_store_to_fifo_i)? thresh_pos_i : thresholds_out[0];
   assign thresholds_in[1] = (threshold_store_to_fifo_i)? thresh_neg_i : thresholds_out[1];
   assign thresh_pos = thresholds_out[0];
   assign thresh_neg = thresholds_out[1];
   assign sum_tot = sum_pos - sum_neg;


   genvar                  block;
   genvar                  set;
   genvar                  line;
   genvar                  column;
   generate
      for(set=0;set<2;set++) begin : weightbufferset
         for(line=0;line<K;line++)begin : weightbufferline
            for(column=0;column<K;column++)begin : weightbuffercolumn
               for(block=0;block<WEIGHT_STAGGER;block++) begin : weightbufferblock
                  weightbufferblock #(.N_I(N_I/WEIGHT_STAGGER), .K(1))
                  weightsbuffer (
                                 .data_i(weights_i),
                                 .clk_i(clk_i),
                                 .rst_ni(rst_ni),
                                 .save_enable_i(weights_save_enable[set][block][line][column]),
                                 .test_enable_i(weights_test_enable[set][block][line][column]),
                                 .flush_i(weights_flush[set][block]),
                                 .data_o(weights_interim[set][block][line][column])
                                 );
               end // for (block=0;block<WEIGHT_STAGGER;block++)
            end // for (column=0;column<K;column++)
         end // for (line=0;line<K;line++)
      end // for (set=0;set<2;set++)
   endgenerate

   always_comb begin : weight_bank_selection
      weights_flush = '0;
      if(weights_read_bank_i == 1'b0) begin
         weights_read_interim = weights_interim[0];
         weights_flush[1] = weights_flush_i;
      end else begin
         weights_read_interim = weights_interim[1];
         weights_flush[0] = weights_flush_i;
      end

      for(int j=0;j<K;j++) begin
         for(int n=0;n<K;n++) begin
            for (int slice=0;slice<WEIGHT_STAGGER;slice++) begin
               for (int q=0;q<N_I/WEIGHT_STAGGER;q++) begin
                  weights[j][n][slice*N_I/WEIGHT_STAGGER + q] = weights_read_interim[slice][j][n][q];
               end
            end
         end
      end

   end // always_comb

   logic [FIFO_DATA_WIDTH-2:0] hacky_helper;
   assign hacky_helper = '0;

   always_comb begin : ALU_input_selection
      fifo_pop = 1'b0;
      if(compute_enable_i == 1) begin

         alu_data_in_2 = current_sum_q;

         if (alu_operand_sel_i == ALU_OPERAND_FIFO) begin
            alu_data_in_1 = fifo_data_out;
            fifo_pop = 1;
         end else if (alu_operand_sel_i ==  ALU_OPERAND_PREVIOUS) begin
            alu_data_in_1 = previous_alu_data_out_q;
         end else if (alu_operand_sel_i ==  ALU_OPERAND_ZERO) begin
            alu_data_in_1 = '0;
         end else begin
            alu_data_in_1 = {1'b1, hacky_helper};
         end
      end else begin
         alu_data_in_1 = '0;
         alu_data_in_2 = '0;
         fifo_pop = '0;
      end
   end // block: ALU_input_selection

   always_comb begin : ALU
      if (alu_op_i == ALU_OP_MAX) begin // SUM operation
         alu_data_out = alu_data_in_1 > alu_data_in_2 ? alu_data_in_1 : alu_data_in_2;
      end else if (alu_op_i == ALU_OP_SUM) begin // MAX operation
         alu_data_out = alu_data_in_1 + alu_data_in_2;
      end else begin
         alu_data_out = '0;
      end
   end

   always_comb begin : Pooling_FIFO_Push
      fifo_push = 1'b0;
      // Push back to FIFO
      if (pooling_store_to_fifo_i == 1) begin
         if(compute_enable_i) begin
            fifo_push = 1;
         end
      end
   end

   always_comb begin : Output_Generation // Handle multiplexing of outputs

      // Multiplex the input into the decider stage: Either ALU or tern_mult result
      if (multiplexer_i == MULTIPLEXER_CONV) begin : Output_Multiplexer
         threshold_input = current_sum_q;
      end else begin
         threshold_input = alu_data_out;
      end

      // Make thresholding decision on threshold input
      if (threshold_input > thresh_pos)
        out_o = POS;
      else if (threshold_input < thresh_neg)
        out_o = NEG;
      else
        out_o = ZERO;

      fp_out_o = current_sum_q;

   end // always_comb

   // Handle the pipeline stage and storage of previous alu output
   always_ff @(posedge clk_i, negedge rst_ni) begin
      if (~rst_ni) begin
         previous_alu_data_out_q <= '0;
         current_sum_q <= '0;
      end else begin
         if(compute_enable_i == 1) begin
            previous_alu_data_out_q <= alu_data_out;
            current_sum_q <= sum_tot;
         end
      end
   end // always_ff @ (posedge clk_i, negedge rst_ni)

endmodule // out_channel_compute_unit
