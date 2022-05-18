// ----------------------------------------------------------------------
//
// File: cutie_top.sv
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
// This module is the system level interconnection of all submodules.

module cutie_top
  import cutie_params::*;
   #(
     parameter N_I = cutie_params::N_I,
     parameter N_O = cutie_params::N_O,
     parameter IMAGEWIDTH = cutie_params::IMAGEWIDTH,
     parameter IMAGEHEIGHT = cutie_params::IMAGEHEIGHT,
     parameter TCN_WIDTH = cutie_params::TCN_WIDTH,
     parameter K = cutie_params::K,
     parameter LAYER_FIFODEPTH = cutie_params::LAYER_FIFODEPTH,
     parameter POOLING_FIFODEPTH = cutie_params::POOLING_FIFODEPTH,
     parameter THRESHOLD_FIFODEPTH = cutie_params::THRESHOLD_FIFODEPTH,
     parameter WEIGHT_STAGGER = cutie_params::WEIGHT_STAGGER,
     parameter PIPELINEDEPTH = cutie_params::PIPELINEDEPTH,
     parameter WEIGHTBANKDEPTH = cutie_params::WEIGHTBANKDEPTH,
     parameter NUMACTMEMBANKSETS = cutie_params::NUMACTMEMBANKSETS,
     parameter NUM_LAYERS = cutie_params::NUM_LAYERS,

     parameter int unsigned OCUDELAY = 1,
     parameter int unsigned COMPUTEDELAY = PIPELINEDEPTH - 1 + OCUDELAY,

     parameter int unsigned POOLING_USAGEWIDTH = POOLING_FIFODEPTH > 1 ? $clog2(POOLING_FIFODEPTH) : 1,
     parameter int unsigned THRESHOLD_USAGEWIDTH = THRESHOLD_FIFODEPTH > 1 ? $clog2(THRESHOLD_FIFODEPTH) : 1,

     parameter int unsigned EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER,
     parameter int unsigned PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5, // Round up number of trits per word, cut excess
     parameter int unsigned PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8,
     parameter int unsigned EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2,
     parameter int unsigned EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS,
     parameter int unsigned NUMDECODERSPERBANK = PHYSICALBITSPERWORD/8,

     parameter int unsigned NUMWRITEBANKS = N_O/(N_I/WEIGHT_STAGGER),
     parameter int unsigned NUMENCODERSPERBANK = (N_O/NUMWRITEBANKS+4)/5,

     parameter int unsigned NUMBANKS = K*WEIGHT_STAGGER, // Need K*NI trits per cycle
     parameter int unsigned TOTNUMTRITS = IMAGEWIDTH*IMAGEHEIGHT*N_I,
     parameter int unsigned TRITSPERBANK = (TOTNUMTRITS+NUMBANKS-1)/NUMBANKS,
     parameter int unsigned ACTMEMBANKDEPTH = (TRITSPERBANK+EFFECTIVETRITSPERWORD-1)/EFFECTIVETRITSPERWORD,
     parameter int unsigned ACTMEMBANKADDRESSDEPTH = $clog2(ACTMEMBANKDEPTH),

     parameter int unsigned LEFTSHIFTBITWIDTH = NUMBANKS > 1 ? $clog2(NUMBANKS) : 1,
     parameter int unsigned BANKSETSBITWIDTH = NUMACTMEMBANKSETS > 1 ? $clog2(NUMACTMEMBANKSETS) : 1,
     parameter int unsigned SPLITBITWIDTH = $clog2(WEIGHT_STAGGER)+1,

     parameter int unsigned COLADDRESSWIDTH = $clog2(IMAGEWIDTH),
     parameter int unsigned ROWADDRESSWIDTH = $clog2(IMAGEHEIGHT),
     parameter int unsigned TBROWADDRESSWIDTH = $clog2(K),

     parameter int unsigned WEIGHTMEMFULLADDRESSBITWIDTH = $clog2(WEIGHTBANKDEPTH),
     parameter int unsigned ACTMEMFULLADDRESSBITWIDTH = $clog2(NUMBANKS*ACTMEMBANKDEPTH)

     )
   (
    input logic                                                                  clk_i,
    input logic                                                                  rst_ni,
    ///////////////////////////////// External actmem access signals /////////////////////////////////
    input logic [BANKSETSBITWIDTH-1:0]                                           actmem_external_bank_set_i,
    input logic                                                                  actmem_external_we_i,
    input logic                                                                  actmem_external_req_i,
    input logic [ACTMEMFULLADDRESSBITWIDTH-1:0]                                  actmem_external_addr_i,
    input logic [PHYSICALBITSPERWORD-1:0]                                        actmem_external_wdata_i,

    ///////////////////////////////// External weightmem access signals /////////////////////////////////
    input logic [$clog2(N_O)-1:0]                                                weightmem_external_bank_i,
    input logic                                                                  weightmem_external_we_i,
    input logic                                                                  weightmem_external_req_i,
    input logic [WEIGHTMEMFULLADDRESSBITWIDTH-1:0]                               weightmem_external_addr_i,
    input logic [PHYSICALBITSPERWORD-1:0]                                        weightmem_external_wdata_i,

    input logic signed [$clog2(K*K*N_I):0]                                       ocu_thresh_pos_i, ocu_thresh_neg_i,
    ///////////////////////////////// Signals with a leading underscore are not yet final, might still change /////////////////////////////////
    input logic [0:N_O-1]                                                        ocu_thresholds_save_enable_i,

    input logic                                                                  LUCA_store_to_fifo_i,
    input logic                                                                  LUCA_testmode_i,
    input logic unsigned [$clog2(IMAGEWIDTH):0]                                  LUCA_layer_imagewidth_i,
    input logic unsigned [$clog2(IMAGEHEIGHT):0]                                 LUCA_layer_imageheight_i,
    input logic unsigned [$clog2(K):0]                                           LUCA_layer_k_i,
    input logic unsigned [$clog2(N_I):0]                                         LUCA_layer_ni_i,
    input logic unsigned [$clog2(N_O):0]                                         LUCA_layer_no_i,
    input logic unsigned [$clog2(K)-1:0]                                         LUCA_layer_stride_width_i,
    input logic unsigned [$clog2(K)-1:0]                                         LUCA_layer_stride_height_i,
    input logic                                                                  LUCA_layer_padding_type_i,
    input logic                                                                  LUCA_pooling_enable_i,
    input logic                                                                  LUCA_pooling_pooling_type_i,
    input logic unsigned [$clog2(K)-1:0]                                         LUCA_pooling_kernel_i,
    input logic                                                                  LUCA_pooling_padding_type_i,
    input logic                                                                  LUCA_layer_skip_in_i,
    input logic                                                                  LUCA_layer_skip_out_i,
    input logic                                                                  LUCA_layer_is_tcn_i,
    input logic [$clog2(TCN_WIDTH)-1:0]                                          LUCA_layer_tcn_width_i,
    input logic [$clog2(TCN_WIDTH)-1:0]                                          LUCA_layer_tcn_width_mod_dil_i,
    input logic [$clog2(K)-1:0]                                                  LUCA_layer_tcn_k_i,

    input logic                                                                  LUCA_compute_disable_i,

    output logic [PHYSICALBITSPERWORD-1:0]                                       actmem_external_acts_o,
    output logic                                                                 actmem_external_valid_o,

    output logic [PHYSICALBITSPERWORD-1:0]                                       weightmem_external_weights_o,
    output logic                                                                 weightmem_external_valid_o,

    output logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1][$clog2(K*K*N_I):0] fp_output_o,

    output logic                                                                 compute_done_o
    /*AUTOARG*/);

   import enums_linebuffer::*;
   import enums_conv_layer::*;
   import cutie_params::*;

   logic                                                                         clk, rst;

   assign clk = clk_i;
   assign rst = rst_ni;

   ///////////////////////////////// ACTMEM WRITE CONTROLLER SIGNALS /////////////////////////////////

   logic                                                                         actmem_write_ctrl_latch_new_layer_i;
   logic [$clog2(N_O):0]                                                         actmem_write_ctrl_layer_no_i;
   logic [0:NUMWRITEBANKS-1][PHYSICALBITSPERWORD-1:0]                            actmem_write_ctrl_wdata_in_i;
   logic                                                                         actmem_write_ctrl_valid_i;

   logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0]                                 actmem_write_ctrl_wdata_out_o;
   logic [0:NUMBANKS-1]                                                          actmem_write_ctrl_write_enable_o;
   logic [0:NUMBANKS-1][ACTMEMBANKADDRESSDEPTH-1:0]                              actmem_write_ctrl_write_addr_o;

   ///////////////////////////////// END ACTMEM WRITE CONTROLLER SIGNALS /////////////////////////////////

   ///////////////////////////////// ACTMEM SIGNALS /////////////////////////////////

   logic [0:NUMBANKS-1]                                                          actmem_read_enable_i;
   logic [0:BANKSETSBITWIDTH-1]                                                  actmem_read_enable_bank_set_i;
   logic [0:NUMBANKS-1][$clog2(ACTMEMBANKDEPTH)-1:0]                             actmem_read_addr_i;

   logic [0:NUMBANKS-1]                                                          actmem_write_enable_i;
   logic [0:BANKSETSBITWIDTH-1]                                                  actmem_write_enable_bank_set_i;
   logic [0:NUMBANKS-1][$clog2(ACTMEMBANKDEPTH)-1:0]                             actmem_write_addr_i;

   logic [0:NUMBANKS-1][PHYSICALBITSPERWORD-1:0]                                 actmem_wdata_i;

   logic [LEFTSHIFTBITWIDTH-1:0]                                                 actmem_left_shift_i;
   logic [SPLITBITWIDTH-1:0]                                                     actmem_scatter_coefficient_i;
   logic [$clog2(WEIGHT_STAGGER):0]                                              actmem_pixelwidth_i;
   logic                                                                         actmem_tcn_actmem_set_shift_i;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 actmem_tcn_actmem_read_shift_i;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 actmem_tcn_actmem_write_shift_i;


   logic [0:NUMBANKS-1]                                                          actmem_ready_o;
   logic [0:NUMBANKS-1]                                                          actmem_rw_collision_o;
   logic [0:K-1][0:N_I-1][1:0]                                                   actmem_acts_o;

   ///////////////////////////////// END ACTMEM SIGNALS /////////////////////////////////

   // logic [0:COMPUTEDELAY-1]                           pipelined_tilebuffer_controller_new_layer_ready_q, pipelined_tilebuffer_controller_new_layer_ready_d;

   ///////////////////////////////// LINEBUFFER SIGNALS /////////////////////////////////
   logic [0:K-1][0:N_I-1][1:0]                                                   linebuffer_acts_i;
   logic                                                                         linebuffer_flush_i;
   logic                                                                         linebuffer_valid_i;
   logic [COLADDRESSWIDTH:0]                                                     linebuffer_layer_imagewidth_i;
   logic [ROWADDRESSWIDTH:0]                                                     linebuffer_layer_imageheight_i;
   logic                                                                         linebuffer_write_enable_i;
   logic                                                                         linebuffer_wrap_around_save_enable_i;
   logic [COLADDRESSWIDTH-1:0]                                                   linebuffer_write_col_i;
   logic                                                                         linebuffer_read_enable_i;
   logic [COLADDRESSWIDTH-1:0]                                                   linebuffer_read_col_i;
   logic [TBROWADDRESSWIDTH-1:0]                                                 linebuffer_read_row_i;
   logic [0:K-1][0:K-1][0:N_I-1][1:0]                                            linebuffer_acts_o;
   ///////////////////////////////// LINEBUFFER SIGNALS END /////////////////////////////////


   //////////////////////////// LINEBUFFER MASTER CONTROLLER  SIGNALS ///////////////////////////////
   logic                                                                         linebuffer_master_controller_new_layer_i;
   logic                                                                         linebuffer_master_controller_valid_i;
   logic                                                                         linebuffer_master_controller_ready_i;
   logic [$clog2(K)-1:0]                                                         linebuffer_master_controller_layer_stride_width_i;
   logic [$clog2(K)-1:0]                                                         linebuffer_master_controller_layer_stride_height_i;
   enums_conv_layer::padding_type                     linebuffer_master_controller_layer_padding_type_i;
   logic [COLADDRESSWIDTH:0]                                                     linebuffer_master_controller_layer_imagewidth_i;
   logic [ROWADDRESSWIDTH:0]                                                     linebuffer_master_controller_layer_imageheight_i;
   logic [$clog2(N_I):0]                                                         linebuffer_master_controller_layer_ni_i;
   logic                                                                         linebuffer_master_controller_layer_is_tcn_i;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 linebuffer_master_controller_layer_tcn_width_i;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 linebuffer_master_controller_layer_tcn_width_mod_dil_i;
   logic [$clog2(K)-1:0]                                                         linebuffer_master_controller_layer_tcn_k_i;
   logic                                                                         linebuffer_master_controller_ready_read_o;
   logic                                                                         linebuffer_master_controller_ready_write_o;
   logic [COLADDRESSWIDTH-1:0]                                                   linebuffer_master_controller_read_col_o;
   logic [ROWADDRESSWIDTH-1:0]                                                   linebuffer_master_controller_read_row_o;
   logic [COLADDRESSWIDTH-1:0]                                                   linebuffer_master_controller_write_col_o;
   logic [ROWADDRESSWIDTH-1:0]                                                   linebuffer_master_controller_write_row_o;
   logic                                                                         linebuffer_master_controller_wrap_around_save_enable_o;
   logic                                                                         linebuffer_master_controller_done_o;
   logic                                                                         linebuffer_master_controller_flush_o;
   ///////////////////////////// LINEBUFFER MASTER CONTROLLER  SIGNALS END ////////////////////////

   ///////////////////////////////// ACTMEM2LB CONTROLLER SIGNALS /////////////////////////////////
   logic                                                                         actmem2lb_controller_new_layer_i;
   logic [$clog2(K)-1:0]                                                         actmem2lb_controller_layer_stride_width_i;
   logic [$clog2(K)-1:0]                                                         actmem2lb_controller_layer_stride_height_i;
   enums_conv_layer::padding_type                     actmem2lb_controller_layer_padding_type_i;
   logic [COLADDRESSWIDTH:0]                                                     actmem2lb_controller_layer_imagewidth_i;
   logic [ROWADDRESSWIDTH:0]                                                     actmem2lb_controller_layer_imageheight_i;
   logic [$clog2(N_I):0]                                                         actmem2lb_controller_layer_ni_i;
   logic                                                                         actmem2lb_controller_ready_i;
   logic                                                                         actmem2lb_controller_valid_i;
   logic [COLADDRESSWIDTH-1:0]                                                   actmem2lb_controller_write_col_i;
   logic [ROWADDRESSWIDTH-1:0]                                                   actmem2lb_controller_write_row_i;
   logic                                                                         actmem2lb_controller_wrap_around_save_enable_i;
   logic [0:NUMBANKS-1]                                                          actmem2lb_controller_read_enable_vector_o;
   logic [0:NUMBANKS-1][ACTMEMBANKADDRESSDEPTH-1:0]                              actmem2lb_controller_read_addr_o;
   logic [LEFTSHIFTBITWIDTH-1:0]                                                 actmem2lb_controller_left_shift_o;
   logic [SPLITBITWIDTH-1:0]                                                     actmem2lb_controller_scatter_coefficient_o;
   ///////////////////////////////// ACTMEM2LB CONTROLLER SIGNALS END /////////////////////////////////

   ///////////////////////////////// LB2OCU CONTROLLER SIGNALS /////////////////////////////////
   logic                                                                         lb2ocu_controller_new_layer_i;
   logic [$clog2(K)-1:0]                                                         lb2ocu_controller_layer_stride_width_i;
   logic [$clog2(K)-1:0]                                                         lb2ocu_controller_layer_stride_height_i;
   enums_conv_layer::padding_type                     lb2ocu_controller_layer_padding_type_i;
   logic [COLADDRESSWIDTH:0]                                                     lb2ocu_controller_layer_imagewidth_i;
   logic [ROWADDRESSWIDTH:0]                                                     lb2ocu_controller_layer_imageheight_i;
   logic [$clog2(N_I):0]                                                         lb2ocu_controller_layer_ni_i;
   logic                                                                         lb2ocu_controller_ready_i;
   logic [COLADDRESSWIDTH-1:0]                                                   lb2ocu_controller_read_col_i;
   logic [ROWADDRESSWIDTH-1:0]                                                   lb2ocu_controller_read_row_i;
   logic [COLADDRESSWIDTH-1:0]                                                   lb2ocu_controller_read_col_o;
   logic [TBROWADDRESSWIDTH-1:0]                                                 lb2ocu_controller_read_row_o;
   ///////////////////////////////// LB2OCU CONTROLLER SIGNALS END /////////////////////////////////


   ///////////////////////////////// LUCA SIGNALS /////////////////////////////////

   logic                                                                         LUCA_tilebuffer_done_i;
   logic [0:PIPELINEDEPTH-1]                                                     LUCA_weightload_done_i;

   logic                                                                         LUCA_testmode_o;
   logic                                                                         LUCA_compute_latch_new_layer_o;
   logic                                                                         LUCA_compute_soft_reset_o;
   logic [$clog2(IMAGEWIDTH):0]                                                  LUCA_compute_imagewidth_o;
   logic [$clog2(IMAGEHEIGHT):0]                                                 LUCA_compute_imageheight_o;
   logic [$clog2(K):0]                                                           LUCA_compute_k_o;
   logic [$clog2(N_I):0]                                                         LUCA_compute_ni_o;
   logic [$clog2(N_O):0]                                                         LUCA_compute_no_o;
   logic [$clog2(K)-1:0]                                                         LUCA_stride_width_o;
   logic [$clog2(K)-1:0]                                                         LUCA_stride_height_o;
   logic                                                                         LUCA_padding_type_o;
   logic                                                                         LUCA_compute_is_tcn_o;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 LUCA_compute_tcn_width_o;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 LUCA_compute_tcn_width_mod_dil_o;
   logic [$clog2(K)-1:0]                                                         LUCA_compute_tcn_k_o;
   logic [$clog2(WEIGHT_STAGGER):0]                                              LUCA_pixelwidth_o;
   logic                                                                         LUCA_tcn_actmem_set_shift_o;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 LUCA_tcn_actmem_read_shift_o;
   logic [$clog2(TCN_WIDTH)-1:0]                                                 LUCA_tcn_actmem_write_shift_o;




   logic                                                                         LUCA_pooling_enable_o;
   logic                                                                         LUCA_pooling_pooling_type_o;
   logic [$clog2(K)-1:0]                                                         LUCA_pooling_kernel_o;
   logic                                                                         LUCA_pooling_padding_type_o;

   logic                                                                         LUCA_layer_skip_in_o;
   logic                                                                         LUCA_layer_skip_out_o;

   logic [$clog2(NUMACTMEMBANKSETS)-1:0]                                         LUCA_readbank_o;
   logic [$clog2(NUMACTMEMBANKSETS)-1:0]                                         LUCA_writebank_o;
   logic [0:PIPELINEDEPTH-1]                                                     LUCA_weights_latch_new_layer_o;
   logic [$clog2(K):0]                                                           LUCA_weights_k_o;
   logic [$clog2(N_I):0]                                                         LUCA_weights_ni_o;
   logic [$clog2(N_O):0]                                                         LUCA_weights_no_o;

   logic [0:PIPELINEDEPTH-1]                                                     LUCA_weights_soft_reset_o;
   logic [0:PIPELINEDEPTH-1]                                                     LUCA_weights_toggle_banks_o;
   logic                                                                         LUCA_fifo_pop_o;
   logic                                                                         LUCA_compute_done_o;

   ///////////////////////////////// END LUCA SIGNALS /////////////////////////////////

   ///////////////////////////////// OCU CONTROLLER SIGNALS /////////////////////////////////

   logic                                                                         ocu_controller_latch_new_layer_i;
   logic [$clog2(N_O):0]                                                         ocu_controller_layer_no_i;
   logic                                                                         ocu_controller_tilebuffer_valid_i;
   logic [0:N_O-1]                                                               ocu_controller_weightmemory_valid_i;

   logic [$clog2(IMAGEWIDTH):0]                                                  ocu_controller_layer_imagewidth_i;
   logic [$clog2(IMAGEHEIGHT):0]                                                 ocu_controller_layer_imageheight_i;
   logic                                                                         ocu_controller_layer_pooling_enable_i;
   logic                                                                         ocu_controller_layer_pooling_pooling_type_i;
   logic [$clog2(K)-1:0]                                                         ocu_controller_layer_pooling_kernel_i;
   logic                                                                         ocu_controller_layer_pooling_padding_type_i;

   logic                                                                         ocu_controller_layer_skip_in_i;
   logic                                                                         ocu_controller_layer_skip_out_i;

   logic [0:PIPELINEDEPTH-1]                                                     ocu_controller_compute_enable_o;
   logic                                                                         ocu_controller_pooling_fifo_flush_o;
   logic                                                                         ocu_controller_pooling_fifo_testmode_o;
   logic                                                                         ocu_controller_pooling_store_to_fifo_o; // 1: Store, 0: Don't store
   logic                                                                         ocu_controller_threshold_fifo_flush_o;
   logic                                                                         ocu_controller_threshold_fifo_testmode_o;
   logic [0:N_O-1]                                                               ocu_controller_threshold_pop_o; // 1: Store, 0: Don't store
   enums_ocu_pool::alu_operand_sel ocu_controller_alu_operand_sel_o; // 01: FIFO, 10: previous result, 00: zero ATTENTION: Choosing 01 also pops from FIFO!
   enums_ocu_pool::multiplexer ocu_controller_multiplexer_o; // 1: Use ALU result, 0: Use current convolution result
   enums_ocu_pool::alu_op ocu_controller_alu_op_o; // 1: Sum, 0: Max
   logic                                                                         ocu_controller_ready_o;
   logic                                                                         ocu_controller_valid_o;

   logic [0:COMPUTEDELAY-1]                                                      pipelined_ocu_controller_valid_q, pipelined_ocu_controller_valid_d;
   logic [0:PIPELINEDEPTH-1]                                                     pipelined_ocu_controller_pooling_store_to_fifo_q, pipelined_ocu_controller_pooling_store_to_fifo_d;
   logic [0:PIPELINEDEPTH-1][1:0]                                                pipelined_ocu_controller_alu_operand_sel_q, pipelined_ocu_controller_alu_operand_sel_d;
   logic [0:PIPELINEDEPTH-1]                                                     pipelined_ocu_controller_alu_op_q, pipelined_ocu_controller_alu_op_d;

   ///////////////////////////////// OCU CONTROLLER SIGNALS END /////////////////////////////////

   ///////////////////////////////// ENCODER BANK SIGNALS /////////////////////////////////

   logic [0:NUMWRITEBANKS-1][0:EFFECTIVETRITSPERWORD-1][1:0]                     pipeline_outputs;
   logic [0:NUMWRITEBANKS-1][0:PHYSICALTRITSPERWORD-1][1:0]                      _encoder_inputs;
   logic [0:NUMWRITEBANKS-1][0:NUMENCODERSPERBANK-1][9:0]                        encoder_inputs;

   logic [0:NUMWRITEBANKS-1][0:NUMENCODERSPERBANK-1][7:0]                        encoder_outputs;
   logic [0:NUMWRITEBANKS-1][PHYSICALBITSPERWORD-1:0]                            actmem_write_input;

   ///////////////////////////////// END ENCODER BANK SIGNALS /////////////////////////////////

   ///////////////////////////////// WEIGHTMEMORY HELPER SIGNALS /////////////////////////////////

   logic [0:N_O-1]                                                               weightmemory_valid_vector;
   logic [0:N_O-1][PHYSICALBITSPERWORD-1:0]                                      weightmemory_external_weights_vector;
   logic [0:N_O-1]                                                               weightmemory_external_valid_vector;

   logic [0:N_O-1]                                                               weightmemory_external_we_vector;
   logic [0:N_O-1]                                                               weightmemory_external_req_vector;
   logic [0:N_O-1] [WEIGHTMEMFULLADDRESSBITWIDTH-1:0]                            weightmemory_external_addr_vector;
   logic [0:N_O-1] [PHYSICALBITSPERWORD-1:0]                                     weightmemory_external_wdata_vector;

   logic [0:N_O-1]                                                               weightmemory_write_enable;
   logic [PIPELINEDEPTH-1:0][0:(N_O/PIPELINEDEPTH)-1]                            __weightmemory_write_enable; // Activation memory outputs are valid

   logic [$clog2(N_O)-1:0]                                                       weightmemory_external_bank_q;

   logic [$clog2(N_O)-1:0]                                                       weightmemory_bank_helper;
   logic [0:N_O-1]                                                               weightmemory_enable_helper;

   ///////////////////////////////// END WEIGHTMEMORY HELPER SIGNALS /////////////////////////////////

   ///////////////////////////////// WEIGHTMEMORY CONTROLLER HELPER SIGNALS /////////////////////////////////

   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1]                            weightmemory_controller_rw_collision_in;
   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1]                            weightmemory_controller_ready_in; // OCU is ready for inputs
   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1]                            weightmemory_controller_valid_in; // Activation memory outputs are valid

   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1]                            weightmemory_controller_ready_out; // OCU is ready for inputs
   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1]                            weightmemory_controller_valid_out; // Activation memory outputs are valid

   ///////////////////////////////// END WEIGHTMEMORY CONTROLLER HELPER SIGNALS /////////////////////////////////

   ///////////////////////////////// OCU HELPER SIGNALS /////////////////////////////////

   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1][1:0]                       immediate_compute_output;
   logic [0:PIPELINEDEPTH-1][0:(N_O/PIPELINEDEPTH)-1][1:0]                       pipelined_compute_output;

   ///////////////////////////////// END OCU HELPER SIGNALS /////////////////////////////////


   actmem_write_controller
     #(
       .N_O(N_O),
       .N_I(N_I),
       .K(K),
       .WEIGHT_STAGGER(WEIGHT_STAGGER),
       .IMAGEWIDTH(IMAGEWIDTH),
       .IMAGEHEIGHT(IMAGEHEIGHT),
       .NUMACTMEMBANKSETS(NUMACTMEMBANKSETS)
       ) actmem_write_ctrl (
                            .clk_i(clk),
                            .rst_ni(rst),
                            .latch_new_layer_i(actmem_write_ctrl_latch_new_layer_i),
                            .layer_no_i(actmem_write_ctrl_layer_no_i),
                            .wdata_i(actmem_write_ctrl_wdata_in_i),
                            .valid_i(actmem_write_ctrl_valid_i),

                            .wdata_o(actmem_write_ctrl_wdata_out_o),
                            .write_enable_o(actmem_write_ctrl_write_enable_o),
                            .write_addr_o(actmem_write_ctrl_write_addr_o)
                            /*AUTOINST*/);


   activationmemory_external_wrapper
     #(
       .N_I(N_I),
       .N_O(N_O),
       .K(K),
       .WEIGHT_STAGGER(WEIGHT_STAGGER),
       .IMAGEWIDTH(IMAGEWIDTH),
       .IMAGEHEIGHT(IMAGEHEIGHT),
       .TCN_WIDTH(TCN_WIDTH),
       .NUMBANKSETS(NUMACTMEMBANKSETS)
       ) actmem (
                 .clk_i(clk),
                 .rst_ni(rst),
                 .external_bank_set_i(actmem_external_bank_set_i),
                 .external_we_i(actmem_external_we_i),
                 .external_req_i(actmem_external_req_i),
                 .external_addr_i(actmem_external_addr_i),
                 .external_wdata_i(actmem_external_wdata_i),
                 .read_enable_i(actmem_read_enable_i),
                 .read_enable_bank_set_i(actmem_read_enable_bank_set_i),
                 .read_addr_i(actmem_read_addr_i),
                 .wdata_i(actmem_wdata_i),
                 .write_addr_i(actmem_write_addr_i),
                 .write_enable_i(actmem_write_enable_i),
                 .write_enable_bank_set_i(actmem_write_enable_bank_set_i),
                 .left_shift_i(actmem_left_shift_i),
                 .scatter_coefficient_i(actmem_scatter_coefficient_i),
                 .pixelwidth_i(actmem_pixelwidth_i),
                 .tcn_actmem_set_shift_i(actmem_tcn_actmem_set_shift_i),
                 .tcn_actmem_read_shift_i(actmem_tcn_actmem_read_shift_i),
                 .tcn_actmem_write_shift_i(actmem_tcn_actmem_write_shift_i),
                 .valid_o(actmem_ready_o),
                 .rw_collision_o(actmem_rw_collision_o),
                 .acts_o(actmem_acts_o),
                 .external_acts_o(actmem_external_acts_o),
                 .external_valid_o(actmem_external_valid_o)
                 /*AUTOINST*/);

   ///////////////////////////////// SYSTEM-LEVEL CONTROL /////////////////////////////////

   LUCA
     #(
       .K(K),
       .N_I(N_I),
       .N_O(N_O),
       .PIPELINEDEPTH(PIPELINEDEPTH),
       .IMAGEWIDTH(IMAGEWIDTH),
       .IMAGEHEIGHT(IMAGEHEIGHT),
       .TCN_WIDTH(TCN_WIDTH),
       .LAYER_FIFODEPTH(LAYER_FIFODEPTH),
       .NUMACTMEMBANKSETS(NUMACTMEMBANKSETS),
       .NUMBANKS(NUMBANKS)
       ) LUCA (
               .clk_i(clk),
               .rst_ni(rst),
               .store_to_fifo_i(LUCA_store_to_fifo_i),
               .testmode_i(LUCA_testmode_i),
               .layer_imagewidth_i(LUCA_layer_imagewidth_i),
               .layer_imageheight_i(LUCA_layer_imageheight_i),
               .layer_k_i(LUCA_layer_k_i),
               .layer_ni_i(LUCA_layer_ni_i),
               .layer_no_i(LUCA_layer_no_i),
               .layer_stride_width_i(LUCA_layer_stride_width_i),
               .layer_stride_height_i(LUCA_layer_stride_height_i),
               .layer_padding_type_i(LUCA_layer_padding_type_i),
               .layer_pooling_enable_i(LUCA_pooling_enable_i),
               .layer_pooling_pooling_type_i(LUCA_pooling_pooling_type_i),
               .layer_pooling_kernel_i(LUCA_pooling_kernel_i),
               .layer_pooling_padding_type_i(LUCA_pooling_padding_type_i),
               .layer_skip_out_i(LUCA_layer_skip_out_i),
               .layer_skip_in_i(LUCA_layer_skip_in_i),
               .layer_is_tcn_i(LUCA_layer_is_tcn_i),
               .layer_tcn_width_i(LUCA_layer_tcn_width_i),
               .layer_tcn_width_mod_dil_i(LUCA_layer_tcn_width_mod_dil_i),
               .layer_tcn_k_i(LUCA_layer_tcn_k_i),
               .compute_disable_i(LUCA_compute_disable_i),
               .tilebuffer_done_i(LUCA_tilebuffer_done_i),
               .weightload_done_i(LUCA_weightload_done_i),
               .testmode_o(LUCA_testmode_o),
               .compute_latch_new_layer_o(LUCA_compute_latch_new_layer_o),
               .compute_soft_reset_o(LUCA_compute_soft_reset_o),
               .compute_imagewidth_o(LUCA_compute_imagewidth_o),
               .compute_imageheight_o(LUCA_compute_imageheight_o),
               .compute_k_o(LUCA_compute_k_o),
               .compute_ni_o(LUCA_compute_ni_o),
               .compute_no_o(LUCA_compute_no_o),
               .stride_width_o(LUCA_stride_width_o),
               .stride_height_o(LUCA_stride_height_o),
               .padding_type_o(LUCA_padding_type_o),
               .pooling_enable_o(LUCA_pooling_enable_o),
               .pooling_pooling_type_o(LUCA_pooling_pooling_type_o),
               .pooling_kernel_o(LUCA_pooling_kernel_o),
               .pooling_padding_type_o(LUCA_pooling_padding_type_o),
               .skip_out_o(LUCA_layer_skip_out_o),
               .skip_in_o(LUCA_layer_skip_in_o),
               .compute_is_tcn_o(LUCA_compute_is_tcn_o),
               .compute_tcn_width_o(LUCA_compute_tcn_width_o),
               .compute_tcn_width_mod_dil_o(LUCA_compute_tcn_width_mod_dil_o),
               .compute_tcn_k_o(LUCA_compute_tcn_k_o),
               .readbank_o(LUCA_readbank_o),
               .writebank_o(LUCA_writebank_o),
               .pixelwidth_o(LUCA_pixelwidth_o),
               .tcn_actmem_set_shift_o(LUCA_tcn_actmem_set_shift_o),
               .tcn_actmem_read_shift_o(LUCA_tcn_actmem_read_shift_o),
               .tcn_actmem_write_shift_o(LUCA_tcn_actmem_write_shift_o),
               .weights_latch_new_layer_o(LUCA_weights_latch_new_layer_o),
               .weights_k_o(LUCA_weights_k_o),
               .weights_ni_o(LUCA_weights_ni_o),
               .weights_no_o(LUCA_weights_no_o),
               .weights_soft_reset_o(LUCA_weights_soft_reset_o),
               .weights_toggle_banks_o(LUCA_weights_toggle_banks_o),
               .fifo_pop_o(LUCA_fifo_pop_o),
               .compute_done_o(LUCA_compute_done_o)
               /*AUTOINST*/
               );

   linebuffer
     #(/*AUTOINSTPARAM*/
       // Parameters
       .N_I                    (N_I),
       .K                      (K),
       .IMAGEWIDTH             (IMAGEWIDTH),
       .IMAGEHEIGHT            (IMAGEHEIGHT),
       .COLADDRESSWIDTH        (COLADDRESSWIDTH),
       .ROWADDRESSWIDTH        (ROWADDRESSWIDTH),
       .TBROWADDRESSWIDTH      (TBROWADDRESSWIDTH))
   linebuffer (/*AUTOINST*/
               // Outputs
               .acts_o                (linebuffer_acts_o),
               // Inputs
               .clk_i                 (clk_i),
               .rst_ni                (rst_ni),
               .acts_i                (linebuffer_acts_i),
               .flush_i               (linebuffer_flush_i),
               .valid_i               (linebuffer_valid_i),
               .layer_imagewidth_i    (linebuffer_layer_imagewidth_i),
               .layer_imageheight_i   (linebuffer_layer_imageheight_i),
               .write_enable_i        (linebuffer_write_enable_i),
               .wrap_around_save_enable_i(linebuffer_wrap_around_save_enable_i),
               .write_col_i           (linebuffer_write_col_i),
               .read_enable_i         (linebuffer_read_enable_i),
               .read_col_i            (linebuffer_read_col_i),
               .read_row_i            (linebuffer_read_row_i));

   linebuffer_master_controller
     #(/*AUTOINSTPARAM*/
       // Parameters
       .N_I                  (N_I),
       .K                    (K),
       .IMAGEWIDTH           (IMAGEWIDTH),
       .IMAGEHEIGHT          (IMAGEHEIGHT),
       .COLADDRESSWIDTH      (COLADDRESSWIDTH),
       .ROWADDRESSWIDTH      (ROWADDRESSWIDTH),
       .TCN_WIDTH            (TCN_WIDTH)
       )
   linebuffer_master_controller (/*AUTOINST*/
                                 // Outputs
                                 .ready_read_o          (linebuffer_master_controller_ready_read_o),
                                 .ready_write_o         (linebuffer_master_controller_ready_write_o),
                                 .read_col_o            (linebuffer_master_controller_read_col_o),
                                 .read_row_o            (linebuffer_master_controller_read_row_o),
                                 .write_col_o           (linebuffer_master_controller_write_col_o),
                                 .write_row_o           (linebuffer_master_controller_write_row_o),
                                 .wrap_around_save_enable_o(linebuffer_master_controller_wrap_around_save_enable_o),
                                 .done_o                (linebuffer_master_controller_done_o),
                                 .flush_o               (linebuffer_master_controller_flush_o),
                                 // Inputs
                                 .clk_i                 (clk_i),
                                 .rst_ni                (rst_ni),
                                 .new_layer_i           (linebuffer_master_controller_new_layer_i),
                                 .valid_i               (linebuffer_master_controller_valid_i),
                                 .ready_i               (linebuffer_master_controller_ready_i),
                                 .layer_stride_width_i  (linebuffer_master_controller_layer_stride_width_i),
                                 .layer_stride_height_i (linebuffer_master_controller_layer_stride_height_i),
                                 .layer_padding_type_i  (linebuffer_master_controller_layer_padding_type_i),
                                 .layer_imagewidth_i    (linebuffer_master_controller_layer_imagewidth_i),
                                 .layer_imageheight_i   (linebuffer_master_controller_layer_imageheight_i),
                                 .layer_ni_i            (linebuffer_master_controller_layer_ni_i),
                                 .layer_is_tcn_i        (linebuffer_master_controller_layer_is_tcn_i),
                                 .layer_tcn_width_mod_dil_i  (linebuffer_master_controller_layer_tcn_width_mod_dil_i),
                                 .layer_tcn_k_i         (linebuffer_master_controller_layer_tcn_k_i));

   actmem2lb_controller
     #(/*AUTOINSTPARAM*/
       // Parameters
       .N_I                  (N_I),
       .K                    (K),
       .IMAGEWIDTH           (IMAGEWIDTH),
       .IMAGEHEIGHT          (IMAGEHEIGHT),
       .COLADDRESSWIDTH      (COLADDRESSWIDTH),
       .ROWADDRESSWIDTH      (ROWADDRESSWIDTH),
       .WEIGHT_STAGGER       (WEIGHT_STAGGER),
       .NUMACTMEMBANKSETS    (NUMACTMEMBANKSETS),
       .EFFECTIVETRITSPERWORD(EFFECTIVETRITSPERWORD),
       .PHYSICALTRITSPERWORD (PHYSICALTRITSPERWORD),
       .PHYSICALBITSPERWORD  (PHYSICALBITSPERWORD),
       .EXCESSBITS           (EXCESSBITS),
       .EFFECTIVEWORDWIDTH   (EFFECTIVEWORDWIDTH),
       .NUMDECODERSPERBANK   (NUMDECODERSPERBANK),
       .NUMBANKS             (NUMBANKS),
       .TOTNUMTRITS          (TOTNUMTRITS),
       .TRITSPERBANK         (TRITSPERBANK),
       .BANKDEPTH            (ACTMEMBANKDEPTH),
       .LEFTSHIFTBITWIDTH    (LEFTSHIFTBITWIDTH),
       .SPLITWIDTH           (SPLITBITWIDTH))
   actmem2lb_controller (/*AUTOINST*/
                         // Outputs
                         .read_enable_vector_o(actmem2lb_controller_read_enable_vector_o),
                         .read_addr_o        (actmem2lb_controller_read_addr_o),
                         .left_shift_o       (actmem2lb_controller_left_shift_o),
                         .scatter_coefficient_o(actmem2lb_controller_scatter_coefficient_o),
                         // Inputs
                         .clk_i              (clk_i),
                         .rst_ni             (rst_ni),
                         .new_layer_i        (actmem2lb_controller_new_layer_i),
                         .layer_imagewidth_i (actmem2lb_controller_layer_imagewidth_i),
                         .layer_imageheight_i(actmem2lb_controller_layer_imageheight_i),
                         .layer_ni_i         (actmem2lb_controller_layer_ni_i),
                         .ready_i            (actmem2lb_controller_ready_i),
                         .valid_i            (actmem2lb_controller_valid_i),
                         .write_col_i        (actmem2lb_controller_write_col_i),
                         .write_row_i        (actmem2lb_controller_write_row_i),
                         .wrap_around_save_enable_i(actmem2lb_controller_wrap_around_save_enable_i));

   lb2ocu_controller
     #(/*AUTOINSTPARAM*/
       // Parameters
       .N_I             (N_I),
       .K               (K),
       .IMAGEWIDTH      (IMAGEWIDTH),
       .IMAGEHEIGHT     (IMAGEHEIGHT),
       .COLADDRESSWIDTH (COLADDRESSWIDTH),
       .ROWADDRESSWIDTH (ROWADDRESSWIDTH),
       .TBROWADDRESSWIDTH(TBROWADDRESSWIDTH))
   lb2ocu_controller (/*AUTOINST*/
                      // Outputs
                      .read_col_o         (lb2ocu_controller_read_col_o),
                      .read_row_o         (lb2ocu_controller_read_row_o),
                      // Inputs
                      .clk_i                 (clk_i),
                      .rst_ni                (rst_ni),
                      .new_layer_i           (lb2ocu_controller_new_layer_i),
                      .layer_stride_width_i  (lb2ocu_controller_layer_stride_width_i),
                      .layer_stride_height_i (lb2ocu_controller_layer_stride_height_i),
                      .layer_padding_type_i  (lb2ocu_controller_layer_padding_type_i),
                      .layer_imagewidth_i    (lb2ocu_controller_layer_imagewidth_i),
                      .layer_imageheight_i   (lb2ocu_controller_layer_imageheight_i),
                      .layer_ni_i            (lb2ocu_controller_layer_ni_i),
                      .ready_i               (lb2ocu_controller_ready_i),
                      .read_col_i            (lb2ocu_controller_read_col_i),
                      .read_row_i            (lb2ocu_controller_read_row_i));
   ocu_controller
     #(
       .PIPELINEDEPTH(PIPELINEDEPTH),
       .N_O(N_O),
       .K(K),
       .IMAGEWIDTH(IMAGEWIDTH),
       .IMAGEHEIGHT(IMAGEHEIGHT)
       )
   ocu_controller (
                   .clk_i(clk),
                   .rst_ni(rst),
                   .latch_new_layer_i(ocu_controller_latch_new_layer_i),
                   .layer_no_i(ocu_controller_layer_no_i),
                   .layer_imagewidth_i(ocu_controller_layer_imagewidth_i),
                   .layer_imageheight_i(ocu_controller_layer_imageheight_i),
                   .layer_pooling_enable_i(ocu_controller_layer_pooling_enable_i),
                   .layer_pooling_kernel_i(ocu_controller_layer_pooling_kernel_i),
                   .layer_pooling_pooling_type_i(ocu_controller_layer_pooling_pooling_type_i),
                   .layer_pooling_padding_type_i(ocu_controller_layer_pooling_padding_type_i),
                   .layer_skip_in_i(ocu_controller_layer_skip_in_i),
                   .layer_skip_out_i(ocu_controller_layer_skip_out_i),
                   .tilebuffer_valid_i(ocu_controller_tilebuffer_valid_i),
                   .weightmemory_valid_i(ocu_controller_weightmemory_valid_i),
                   .compute_enable_o(ocu_controller_compute_enable_o),
                   .pooling_fifo_flush_o(ocu_controller_pooling_fifo_flush_o),
                   .pooling_fifo_testmode_o(ocu_controller_pooling_fifo_testmode_o),
                   .pooling_store_to_fifo_o(ocu_controller_pooling_store_to_fifo_o),
                   .threshold_fifo_flush_o(ocu_controller_threshold_fifo_flush_o),
                   .threshold_fifo_testmode_o(ocu_controller_threshold_fifo_testmode_o),
                   .threshold_pop_o(ocu_controller_threshold_pop_o),
                   .alu_operand_sel_o(ocu_controller_alu_operand_sel_o),
                   .multiplexer_o(ocu_controller_multiplexer_o),
                   .alu_op_o(ocu_controller_alu_op_o),
                   .ready_o(ocu_controller_ready_o),
                   .valid_o(ocu_controller_valid_o)
                   /*AUTOINST*/);

   ///////////////////////////////// END SYSTEM-LEVEL CONTROL /////////////////////////////////


   ///////////////////////////////// COMPUTE CORE /////////////////////////////////

   logic [0:PIPELINEDEPTH-1][0:K-1][0:K-1][0:N_I-1][1:0]                         acts_pipeline_d, acts_pipeline;

   ///////////////////////////////// INPUT REGISTER FOR PIPELINE /////////////////////////////////

   logic [0:K-1][0:K-1][0:N_I-1][1:0]                                            acts_buffer_q;
   logic                                                                         tilebuffer_valid_q;

   always_ff @(posedge clk, negedge rst) begin
      if (~rst) begin
         acts_buffer_q <= '0;
         tilebuffer_valid_q <= '0;
      end else begin
         tilebuffer_valid_q <= linebuffer_master_controller_ready_read_o;
         if(linebuffer_master_controller_ready_read_o == 1) begin
            acts_buffer_q <= linebuffer_acts_o;
         end
      end
   end // always_ff @ (posedge clk, negedge rst)



   ///////////////////////////////// END INPUT REGISTER FOR PIPELINE /////////////////////////////////

   //assign acts_pipeline[0] = tilebuffer_acts_out_o;
   assign acts_pipeline[0] = acts_buffer_q;

   ///////////////////////////////// PIPELINE STAGES /////////////////////////////////

   genvar                                                    pipelinestage;
   genvar                                                    localmodulenum;
   generate
      for(pipelinestage=0;pipelinestage<PIPELINEDEPTH;pipelinestage++) begin: pipeline

         logic [0:(N_O/PIPELINEDEPTH)-1][1:0]                  pipeline_output;

         logic [0:(PIPELINEDEPTH-2)-pipelinestage][0:(N_O/PIPELINEDEPTH)-1][1:0] output_pipeline_d, output_pipeline;
         ///////////////////////////////// PIPELINE STAGE SIGNALS /////////////////////////////////

         if(pipelinestage < PIPELINEDEPTH-1) begin : compute_output_pipeline

            always_comb begin
               output_pipeline_d[0] = immediate_compute_output[pipelinestage];
               for (int i=1;i<PIPELINEDEPTH-pipelinestage-1;i++) begin
                  output_pipeline_d[i] = output_pipeline[i-1];
               end
            end

            assign pipeline_output = output_pipeline[(PIPELINEDEPTH-2)-pipelinestage];

            ///////////////////////////////// PIPELINE FOR OUTPUT /////////////////////////////////

            always_ff @(posedge clk_i, negedge rst_ni) begin
               if(~rst_ni) begin
                  for (int i=1;i<PIPELINEDEPTH-pipelinestage-1;i++) begin
                     output_pipeline[i] <= '0;
                  end
               end else begin
                  output_pipeline <= output_pipeline_d;
               end
            end // always_ff @ (posedge clk_i, negedge rst_ni)

         end else begin // if (pipelinestage < PIPELINEDEPTH-1)
            assign pipeline_output = immediate_compute_output[pipelinestage];
         end // else: !if(pipelinestage < PIPELINEDEPTH-2)

         assign pipelined_compute_output[pipelinestage] = pipeline_output;

         if(PIPELINEDEPTH-pipelinestage>0 && pipelinestage > 0) begin : activations_pipeline

            ///////////////////////////////// PIPELINE FOR ACTIVATIONS /////////////////////////////////

            always_ff @(posedge clk_i, negedge rst_ni) begin
               if(~rst_ni) begin
                  acts_pipeline[pipelinestage] <= '0;
               end else begin
                  if(pipelinestage < LUCA_compute_no_o/(N_O/PIPELINEDEPTH)) begin
                     acts_pipeline[pipelinestage] <= acts_pipeline[pipelinestage-1];
                  end
               end
            end
         end

         ///////////////////////////////// END PIPELINE STAGE SIGNALS /////////////////////////////////

         ///////////////////////////////// WEIGHTMEMORY CONTROLLER SIGNALS /////////////////////////////////

         logic weightmemory_controller_latch_new_layer_i;
         logic unsigned [$clog2(K):0] weightmemory_controller_layer_k_i; // For MVP disregard kernel variance
         logic unsigned [$clog2(N_I):0] weightmemory_controller_layer_ni_i;
         logic unsigned [$clog2(N_O):0] weightmemory_controller_layer_no_i;
         logic [0:(N_O/PIPELINEDEPTH)-1] weightmemory_controller_rw_collision_i;
         logic [0:(N_O/PIPELINEDEPTH)-1] weightmemory_controller_ready_i; // OCU is ready for inputs
         logic [0:(N_O/PIPELINEDEPTH)-1] weightmemory_controller_valid_i; // Activation memory outputs are valid
         logic                           weightmemory_controller_soft_reset_i;
         logic                           weightmemory_controller_toggle_banks_i;

         logic                           weightmemory_controller_mem_read_enable_o;
         logic [$clog2(WEIGHTBANKDEPTH)-1:0] weightmemory_controller_mem_read_addr_o;
         logic                               weightmemory_controller_weights_read_bank_o;
         logic                               weightmemory_controller_weights_save_bank_o;
         logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] weightmemory_controller_weights_save_enable_o;
         logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] weightmemory_controller_weights_test_enable_o;
         logic [0:WEIGHT_STAGGER-1]               weightmemory_controller_weights_flush_o;
         logic                                    weightmemory_controller_ready_o;
         logic                                    weightmemory_controller_valid_o;

         ///////////////////////////////// END WEIGHTMEMORY CONTROLLER SIGNALS /////////////////////////////////

         weightmemory_controller
           #(
             .K(K), .N_I(N_I), .WEIGHT_STAGGER(WEIGHT_STAGGER), .N_O(N_O),
             .BANKDEPTH(WEIGHTBANKDEPTH), .PIPELINEDEPTH(PIPELINEDEPTH), .NUM_LAYERS(NUM_LAYERS))
         weightmemory_controller
           (
            .clk_i(clk),
            .rst_ni(rst),
            .rw_collision_i(weightmemory_controller_rw_collision_i),
            .valid_i(weightmemory_controller_valid_i),
            .ready_i(weightmemory_controller_ready_i),
            .latch_new_layer_i(weightmemory_controller_latch_new_layer_i),
            .layer_k_i(weightmemory_controller_layer_k_i),
            .layer_ni_i(weightmemory_controller_layer_ni_i),
            .layer_no_i(weightmemory_controller_layer_no_i),
            .soft_reset_i(weightmemory_controller_soft_reset_i),
            .toggle_banks_i(weightmemory_controller_toggle_banks_i),
            .mem_read_enable_o(weightmemory_controller_mem_read_enable_o),
            .mem_read_addr_o(weightmemory_controller_mem_read_addr_o),
            .weights_read_bank_o(weightmemory_controller_weights_read_bank_o),
            .weights_save_bank_o(weightmemory_controller_weights_save_bank_o),
            .weights_save_enable_o(weightmemory_controller_weights_save_enable_o),
            .weights_test_enable_o(weightmemory_controller_weights_test_enable_o),
            .weights_flush_o(weightmemory_controller_weights_flush_o),
            .ready_o(weightmemory_controller_ready_o),
            .valid_o(weightmemory_controller_valid_o)
            /*AUTOINST*/);

         ///////////////////////////////// WEIGHTMEMORY CONTROLLER SIGNAL CONNECTIONS /////////////////////////////////

         assign weightmemory_controller_latch_new_layer_i = LUCA_weights_latch_new_layer_o[pipelinestage];
         assign weightmemory_controller_layer_k_i =  LUCA_weights_k_o; // For MVP disregard kernel variance
         assign weightmemory_controller_layer_ni_i = LUCA_weights_ni_o;
         assign weightmemory_controller_layer_no_i = LUCA_weights_no_o;
         assign weightmemory_controller_soft_reset_i = LUCA_weights_soft_reset_o[pipelinestage];
         assign weightmemory_controller_toggle_banks_i = LUCA_weights_toggle_banks_o[pipelinestage];

         assign weightmemory_controller_rw_collision_i = weightmemory_controller_rw_collision_in[pipelinestage];
         assign weightmemory_controller_ready_i =  weightmemory_controller_ready_in[pipelinestage]; // OCU is ready for inputs
         assign weightmemory_controller_valid_i = weightmemory_controller_valid_in[pipelinestage]; // Activation memory outputs are valid

         ///////////////////////////////// END WEIGHTMEMORY CONTROLLER SIGNAL CONNECTIONS /////////////////////////////////


         for(localmodulenum=0;localmodulenum<(N_O/PIPELINEDEPTH);localmodulenum++) begin: compute_block

            ///////////////////////////////// OCU SIGNALS /////////////////////////////////

            logic [0:(N_I/WEIGHT_STAGGER)-1][1:0] ocu_weights_i;
            logic [0:K-1][0:K-1][0:N_I-1][1:0]    ocu_acts_i;
            enums_ocu_pool::alu_operand_sel ocu_alu_operand_sel_i;
            enums_ocu_pool::multiplexer ocu_multiplexer_i;
            enums_ocu_pool::alu_op ocu_alu_op_i;
            logic                                 ocu_pooling_fifo_flush_i;
            logic                                 ocu_pooling_fifo_testmode_i;
            logic                                 ocu_pooling_store_to_fifo_i;
            logic                                 ocu_threshold_fifo_flush_i;
            logic                                 ocu_threshold_fifo_testmode_i;
            logic                                 ocu_threshold_store_to_fifo_iocu_threshold_store_to_fifo_i;
            logic                                 ocu_threshold_pop_i;
            logic                                 ocu_weights_read_bank_i;
            logic                                 ocu_weights_save_bank_i;
            logic                                 ocu_compute_enable_i;
            logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] ocu_weights_save_enable_i;
            logic [0:WEIGHT_STAGGER-1][0:K-1][0:K-1] ocu_weights_test_enable_i;
            logic [0:WEIGHT_STAGGER-1]               ocu_weights_flush_i;
            //logic                                    local_ocu_thresholds_save_enable_i;

            logic [1:0]                              ocu_out_o;

            ///////////////////////////////// END OCU SIGNALS /////////////////////////////////
            ///////////////////////////////// WEIGHTMEMORY SIGNALS /////////////////////////////////

            logic                                    weightmemory_read_enable_i;
            logic [PHYSICALBITSPERWORD-1:0]          weightmemory_wdata_i; // Data for up to all OCUs at once
            logic [$clog2(WEIGHTBANKDEPTH)-1:0]      weightmemory_read_addr_i; // Addresses for all memories
            logic [$clog2(WEIGHTBANKDEPTH)-1:0]      weightmemory_write_addr_i; // Addresses for all memories
            logic                                    weightmemory_write_enable_i; // Write enable for all memories

            logic                                    weightmemory_ready_o;
            logic                                    weightmemory_rw_collision_o;
            logic [0:EFFECTIVETRITSPERWORD-1][1:0]   weightmemory_weights_o;
            ///////////////////////////////// END WEIGHTMEMORY SIGNALS /////////////////////////////////

            ocu_pool_weights
              #(.K(K),
                .N_I(N_I),
                .POOLING_FIFODEPTH(POOLING_FIFODEPTH),
                .WEIGHT_STAGGER(WEIGHT_STAGGER),
                .THRESHOLD_FIFODEPTH(THRESHOLD_FIFODEPTH)
                ) OCU (
                       .clk_i(clk),
                       .rst_ni(rst),
                       .weights_i(ocu_weights_i),
                       .acts_i(ocu_acts_i),
                       .thresh_pos_i(ocu_thresh_pos_i),
                       .thresh_neg_i(ocu_thresh_neg_i),
                       .pooling_fifo_flush_i(ocu_pooling_fifo_flush_i),
                       .pooling_fifo_testmode_i(ocu_pooling_fifo_testmode_i),
                       .pooling_store_to_fifo_i(ocu_pooling_store_to_fifo_i),
                       .threshold_fifo_flush_i(ocu_threshold_fifo_flush_i),
                       .threshold_fifo_testmode_i(ocu_threshold_fifo_testmode_i),
                       .threshold_store_to_fifo_i(ocu_threshold_store_to_fifo_i),
                       .threshold_pop_i(ocu_threshold_pop_i),
                       .alu_operand_sel_i(ocu_alu_operand_sel_i),
                       .multiplexer_i(ocu_multiplexer_i),
                       .alu_op_i(ocu_alu_op_i),
                       .compute_enable_i(ocu_compute_enable_i),
                       .weights_read_bank_i(ocu_weights_read_bank_i),
                       .weights_save_bank_i(ocu_weights_save_bank_i),
                       .weights_save_enable_i(ocu_weights_save_enable_i),
                       .weights_test_enable_i(ocu_weights_test_enable_i),
                       .weights_flush_i(ocu_weights_flush_i),
                       .out_o(ocu_out_o),
                       .fp_out_o(fp_output_o[pipelinestage][localmodulenum])
                       /*AUTOINST*/);

            assign immediate_compute_output[pipelinestage][localmodulenum] = ocu_out_o;

            weightmemory_external_wrapper
              #(
                .N_I(N_I),
                .K(K),
                .WEIGHT_STAGGER(WEIGHT_STAGGER),
                .BANKDEPTH(WEIGHTBANKDEPTH)
                ) weightmemory_internal_wrapper (
                                                 .clk_i(clk),
                                                 .rst_ni(rst),
                                                 .external_we_i(weightmemory_external_we_vector[localmodulenum + pipelinestage*(N_O/PIPELINEDEPTH)]),
                                                 .external_req_i(weightmemory_external_req_vector[localmodulenum + pipelinestage*(N_O/PIPELINEDEPTH)]),
                                                 .external_addr_i(weightmemory_external_addr_vector[localmodulenum + pipelinestage*(N_O/PIPELINEDEPTH)]),
                                                 .external_wdata_i(weightmemory_external_wdata_vector[localmodulenum + pipelinestage*(N_O/PIPELINEDEPTH)]),
                                                 .read_enable_i(weightmemory_read_enable_i),
                                                 .wdata_i(weightmemory_wdata_i),
                                                 .read_addr_i(weightmemory_read_addr_i),
                                                 .write_addr_i(weightmemory_write_addr_i),
                                                 .write_enable_i(weightmemory_write_enable_i),
                                                 .valid_o(weightmemory_ready_o),
                                                 .rw_collision_o(weightmemory_rw_collision_o),
                                                 .weights_o(weightmemory_weights_o),
                                                 .external_weights_o(weightmemory_external_weights_vector[localmodulenum + pipelinestage*(N_O/PIPELINEDEPTH)]),
                                                 .external_valid_o(weightmemory_external_valid_vector[localmodulenum + pipelinestage*(N_O/PIPELINEDEPTH)])
                                                 /*AUTOINST*/);



            ///////////////////////////////// WEIGHTMEMORY SIGNALS CONNECTIONS /////////////////////////////////

            assign weightmemory_valid_vector[localmodulenum + (N_O/PIPELINEDEPTH)*pipelinestage] = weightmemory_ready_o & weightmemory_rw_collision_o;

            assign weightmemory_controller_ready_in[pipelinestage][localmodulenum] = ocu_controller_ready_o;
            assign weightmemory_controller_rw_collision_in[pipelinestage][localmodulenum] = weightmemory_rw_collision_o;
            assign weightmemory_controller_valid_in[pipelinestage][localmodulenum] = weightmemory_ready_o;

            assign weightmemory_controller_ready_out[pipelinestage][localmodulenum] = weightmemory_controller_ready_o;
            assign weightmemory_controller_valid_out[pipelinestage][localmodulenum] = weightmemory_controller_valid_o;

            assign weightmemory_read_enable_i = weightmemory_controller_mem_read_enable_o;
            assign weightmemory_read_addr_i = weightmemory_controller_mem_read_addr_o; // Addresses for all memories

            // ATTENTION: Zero wired
            assign weightmemory_write_addr_i = 'X; // Addresses for all memories
            assign weightmemory_wdata_i = 'X; // Data for up to all OCUs at once
            assign weightmemory_write_enable_i = '0; // __weightmemory_write_enable[pipelinestage][localmodulenum]; // Write enable for all memories

            ///////////////////////////////// WEIGHTMEMORY SIGNALS CONNECTIONS /////////////////////////////////

            ///////////////////////////////// OCU SIGNALS CONNECTIONS /////////////////////////////////

            assign ocu_weights_i = weightmemory_weights_o;
            assign ocu_alu_operand_sel_i = enums_ocu_pool::alu_operand_sel'(pipelined_ocu_controller_alu_operand_sel_d[pipelinestage]);
            assign ocu_multiplexer_i = ocu_controller_multiplexer_o;
            assign ocu_alu_op_i = ocu_controller_alu_op_o;
            assign ocu_pooling_fifo_flush_i = ocu_controller_pooling_fifo_flush_o;
            assign ocu_pooling_fifo_testmode_i = ocu_controller_pooling_fifo_testmode_o;
            assign ocu_pooling_store_to_fifo_i = pipelined_ocu_controller_pooling_store_to_fifo_d[pipelinestage];
            assign ocu_threshold_fifo_flush_i = ocu_controller_threshold_fifo_flush_o;
            assign ocu_threshold_fifo_testmode_i =  ocu_controller_threshold_fifo_testmode_o;
            assign ocu_threshold_store_to_fifo_i = ocu_thresholds_save_enable_i[localmodulenum + (N_O/PIPELINEDEPTH)*pipelinestage];
            assign ocu_threshold_pop_i = ocu_controller_threshold_pop_o[localmodulenum + (N_O/PIPELINEDEPTH)*pipelinestage];
            assign ocu_weights_read_bank_i = weightmemory_controller_weights_read_bank_o;
            assign ocu_weights_save_bank_i = weightmemory_controller_weights_save_bank_o;
            assign ocu_compute_enable_i = ocu_controller_compute_enable_o[pipelinestage];
            assign ocu_weights_save_enable_i = weightmemory_controller_weights_save_enable_o;
            assign ocu_weights_test_enable_i = weightmemory_controller_weights_test_enable_o;
            assign ocu_weights_flush_i = weightmemory_controller_weights_flush_o;

            //assign ocu_thresholds_save_enable_i = ocu_thresholds_save_enable[localmodulenum + pipelinestage*N_O/PIPELINEDEPTH];

            assign ocu_acts_i = acts_pipeline[pipelinestage];
            //assign ocu_acts_i = tilebuffer_acts_out_o;
            ///////////////////////////////// END OCU SIGNALS CONNECTIONS /////////////////////////////////

         end // for (pipelinestage=0;pipelinestage<PIPELINEDEPTH;pipelinestage++)
      end
   endgenerate
   ///////////////////////////////// END COMPUTE CORE /////////////////////////////////

   ///////////////////////////////// LUCA SIGNAL CONNECTIONS /////////////////////////////////

   assign LUCA_tilebuffer_done_i = linebuffer_master_controller_done_o;
   //assign LUCA_weightload_done_i = weightmemory_controller_ready_out[0];

   always_comb begin
      for(int i=0;i<PIPELINEDEPTH;i++) begin
         LUCA_weightload_done_i[i] = weightmemory_controller_ready_out[i][0];
      end
   end

   ///////////////////////////////// END LUCA SIGNAL CONNECTIONS /////////////////////////////////

   ///////////////////////////////// LINEBUFFER SIGNAL CONNECTIONS /////////////////////////////////
   assign linebuffer_acts_i = actmem_acts_o;
   assign linebuffer_flush_i = linebuffer_master_controller_flush_o;
   assign linebuffer_valid_i = (actmem_ready_o>0)&&(actmem_rw_collision_o == '0);
   assign linebuffer_layer_imagewidth_i = LUCA_compute_imagewidth_o;
   assign linebuffer_layer_imageheight_i = LUCA_compute_imageheight_o;
   assign linebuffer_write_enable_i = linebuffer_master_controller_ready_write_o;
   assign linebuffer_wrap_around_save_enable_i = linebuffer_master_controller_wrap_around_save_enable_o;
   assign linebuffer_write_col_i = linebuffer_master_controller_write_col_o;
   assign linebuffer_read_enable_i = linebuffer_master_controller_ready_read_o;
   assign linebuffer_read_col_i = lb2ocu_controller_read_col_o;
   assign linebuffer_read_row_i = lb2ocu_controller_read_row_o;

   ///////////////////////////////// END LINEBUFFER SIGNAL CONNECTIONS /////////////////////////////////

   ///////////////////////////////// ACTMEM WRITE CTRL SIGNAL CONNECTIONS /////////////////////////////////

   assign actmem_write_ctrl_latch_new_layer_i = LUCA_compute_latch_new_layer_o;
   assign actmem_write_ctrl_layer_no_i = LUCA_compute_no_o;
   assign actmem_write_ctrl_wdata_in_i = actmem_write_input;
   assign actmem_write_ctrl_valid_i = pipelined_ocu_controller_valid_q[COMPUTEDELAY-1];

   ///////////////////////////////// END ACTMEM WRITE CTRL SIGNAL CONNECTIONS /////////////////////////////////

   ///////////////////////////////// ACTMEM SIGNAL CONNECTIONS /////////////////////////////////


   assign actmem_read_enable_i = actmem2lb_controller_read_enable_vector_o;
   assign actmem_read_enable_bank_set_i = LUCA_readbank_o;
   assign actmem_read_addr_i = actmem2lb_controller_read_addr_o;
   assign actmem_left_shift_i = actmem2lb_controller_left_shift_o;
   assign actmem_scatter_coefficient_i = actmem2lb_controller_scatter_coefficient_o;
   assign actmem_pixelwidth_i = LUCA_pixelwidth_o;
   assign actmem_tcn_actmem_set_shift_i = LUCA_tcn_actmem_set_shift_o;
   assign actmem_tcn_actmem_read_shift_i = LUCA_tcn_actmem_read_shift_o;
   assign actmem_tcn_actmem_write_shift_i = LUCA_tcn_actmem_write_shift_o;
   assign actmem_wdata_i = actmem_write_ctrl_wdata_out_o;
   assign actmem_write_enable_i = actmem_write_ctrl_write_enable_o;
   assign actmem_write_addr_i = actmem_write_ctrl_write_addr_o;
   assign actmem_write_enable_bank_set_i = LUCA_writebank_o;

   ///////////////////////////////// END ACTMEM SIGNAL CONNECTIONS /////////////////////////////////

   ///////////////////////////////// LINEBUFFER MASTER CONTROLLER SIGNAL CONNECTIONS /////////////////////////////////

   // assign actmem_tilebuffer_controller_testmode_i = LUCA_testmode_o;
   // assign actmem_tilebuffer_controller_valid_i = (actmem_ready_o>0)&&(actmem_rw_collision_o == '0); // Actually valid, need to rename, TODO
   // assign actmem_tilebuffer_controller_ready_i = weightmemory_controller_valid_out[0][0]; // OCU is ready for s
   assign linebuffer_master_controller_new_layer_i = LUCA_compute_latch_new_layer_o;
   assign linebuffer_master_controller_layer_stride_width_i = LUCA_stride_width_o;
   assign linebuffer_master_controller_layer_stride_height_i = LUCA_stride_height_o;
   assign linebuffer_master_controller_layer_padding_type_i = enums_conv_layer::padding_type'(LUCA_padding_type_o);
   assign linebuffer_master_controller_layer_imagewidth_i = LUCA_compute_imagewidth_o;
   assign linebuffer_master_controller_layer_imageheight_i = LUCA_compute_imageheight_o;
   assign linebuffer_master_controller_layer_ni_i = LUCA_compute_ni_o;
   assign linebuffer_master_controller_layer_is_tcn_i = LUCA_compute_is_tcn_o;
   assign linebuffer_master_controller_layer_tcn_width_mod_dil_i = LUCA_compute_tcn_width_mod_dil_o;
   assign linebuffer_master_controller_layer_tcn_k_i = LUCA_compute_tcn_k_o;
   assign linebuffer_master_controller_valid_i = (actmem_ready_o>0)&&(actmem_rw_collision_o == '0);
   assign linebuffer_master_controller_ready_i = weightmemory_controller_valid_out[0][0];
   // TODO: valid_i = (actmem_ready_o>0)&&(actmem_rw_collision_o == '0)
   // TODO: ready_i = weightmemory_controller_valid_out[0][0];
   ////////////////////// END LINEBUFFER MASTER CONTROLLER SIGNAL CONNECTIONS /////////////////////////

   //////////////////////////// ACTMEM2LB CONTROLLER SIGNAL CONNECTIONS ///////////////////////////////
   assign actmem2lb_controller_new_layer_i = LUCA_compute_latch_new_layer_o;
   assign actmem2lb_controller_layer_stride_width_i = LUCA_stride_width_o;
   assign actmem2lb_controller_layer_stride_height_i = LUCA_stride_height_o;
   assign actmem2lb_controller_layer_padding_type_i = enums_conv_layer::padding_type'(LUCA_padding_type_o);
   assign actmem2lb_controller_layer_imagewidth_i = LUCA_compute_imagewidth_o;
   assign actmem2lb_controller_layer_imageheight_i = LUCA_compute_imageheight_o;
   assign actmem2lb_controller_layer_ni_i = LUCA_compute_ni_o;
   assign actmem2lb_controller_ready_i = linebuffer_master_controller_ready_write_o;
   assign actmem2lb_controller_write_col_i = linebuffer_master_controller_write_col_o;
   assign actmem2lb_controller_write_row_i = linebuffer_master_controller_write_row_o;
   assign actmem2lb_controller_wrap_around_save_enable_i = linebuffer_master_controller_wrap_around_save_enable_o;
   // TODO: assign actmem2lb_controller_valid_i =

   ////////////////////////// END ACTMEM2LB CONTROLLER SIGNAL CONNECTIONS //////////////////////////

   ////////////////////////// LB2OCU CONTROLLER SIGNAL CONNECTIONS /////////////////////////////
   assign lb2ocu_controller_new_layer_i = LUCA_compute_latch_new_layer_o;
   assign lb2ocu_controller_layer_stride_width_i = LUCA_stride_width_o;
   assign lb2ocu_controller_layer_stride_height_i = LUCA_stride_height_o;
   assign lb2ocu_controller_layer_padding_type_i = enums_conv_layer::padding_type'(LUCA_padding_type_o);
   assign lb2ocu_controller_layer_imagewidth_i = LUCA_compute_imagewidth_o;
   assign lb2ocu_controller_layer_imageheight_i = LUCA_compute_imageheight_o;
   assign lb2ocu_controller_layer_ni_i = LUCA_compute_ni_o;
   assign lb2ocu_controller_ready_i = linebuffer_master_controller_ready_read_o;
   assign lb2ocu_controller_read_col_i = linebuffer_master_controller_read_col_o;
   assign lb2ocu_controller_read_row_i = linebuffer_master_controller_read_row_o;
   // /////////////////////// END LB2OCU CONTROLLER SIGNAL CONNECTIONS //////////////////////////

   ///////////////////////////////// OCU CONTROLLER SIGNAL CONNECTIONS //////////////////////////////

   assign ocu_controller_latch_new_layer_i = LUCA_compute_latch_new_layer_o;
   assign ocu_controller_layer_no_i = LUCA_compute_no_o;
   assign ocu_controller_layer_imagewidth_i = LUCA_compute_imagewidth_o;
   assign ocu_controller_layer_imageheight_i = LUCA_compute_imageheight_o;
   assign ocu_controller_layer_pooling_enable_i = LUCA_pooling_enable_o;
   assign ocu_controller_layer_pooling_pooling_type_i = LUCA_pooling_pooling_type_o;
   assign ocu_controller_layer_pooling_kernel_i =  LUCA_pooling_kernel_o;
   assign ocu_controller_layer_pooling_padding_type_i = LUCA_pooling_padding_type_o;
   assign ocu_controller_layer_skip_in_i = LUCA_layer_skip_in_o;
   assign ocu_controller_layer_skip_out_i = LUCA_layer_skip_out_o;

   //assign ocu_controller_tilebuffer_valid_i = actmem_tilebuffer_controller_valid_o;
   assign ocu_controller_tilebuffer_valid_i = tilebuffer_valid_q;
   assign ocu_controller_weightmemory_valid_i = weightmemory_valid_vector;

   ///////////////////////////////// END OCU CONTROLLER SIGNAL CONNECTIONS /////////////////////////////////


   ///////////////////////////////// WEIGHTMEMORY HELPER SIGNAL CONNECTIONS /////////////////////////////////

   always_comb begin : weightmem_external_demultiplex
      weightmemory_external_req_vector = '0;
      weightmemory_external_we_vector = '0;
      weightmemory_external_addr_vector = '0;
      weightmemory_external_wdata_vector = '0;

      weightmemory_external_req_vector[weightmem_external_bank_i] = weightmem_external_req_i;
      weightmemory_external_we_vector[weightmem_external_bank_i] = weightmem_external_we_i;
      weightmemory_external_addr_vector[weightmem_external_bank_i] = weightmem_external_addr_i;
      weightmemory_external_wdata_vector[weightmem_external_bank_i] = weightmem_external_wdata_i;

   end // block: weightmem_external_demultiplex

   ///////////////////////////////// END WEIGHTMEMORY HELPER SIGNAL CONNECTIONS  /////////////////////////////////

   ///////////////////////////////// ENCODER BANK /////////////////////////////////



   always_comb begin
      encoder_inputs = '0;
      _encoder_inputs = '0;
      for (int i=0;i<NUMWRITEBANKS;i++) begin
         for (int j=0;j<EFFECTIVETRITSPERWORD;j++) begin
            _encoder_inputs[i][j] = pipeline_outputs[i][j];
         end
         encoder_inputs[i] = _encoder_inputs[i];
      end
   end
   genvar m;
   genvar n;
   generate
      for (m=0;m<NUMWRITEBANKS;m++) begin: encoderbank
         for (n=0;n<NUMENCODERSPERBANK;n++) begin : encodermodule
            encoder enc (
                         .encoder_i(encoder_inputs[m][n]),
                         .encoder_o(encoder_outputs[m][n])
                         );
         end
         assign actmem_write_input[m] = {>>{encoder_outputs[m]}};
      end
   endgenerate
   assign pipeline_outputs = pipelined_compute_output;

   ///////////////////////////////// END ENCODER BANK /////////////////////////////////

   ///////////////////////////////// OCU GLUE LOGIC /////////////////////////////////

   always_comb begin
      pipelined_ocu_controller_valid_d[0] = ocu_controller_valid_o;
      if (PIPELINEDEPTH > 1) begin
         pipelined_ocu_controller_valid_d[1:COMPUTEDELAY-1] = pipelined_ocu_controller_valid_q[0:COMPUTEDELAY-2];
      end
   end

   always_ff @(posedge clk, negedge rst) begin
      if(~rst) begin
         pipelined_ocu_controller_valid_q <= '0;
      end else begin
         pipelined_ocu_controller_valid_q <= pipelined_ocu_controller_valid_d;
      end
   end

   always_comb begin
      pipelined_ocu_controller_pooling_store_to_fifo_d[0] = ocu_controller_pooling_store_to_fifo_o;
      pipelined_ocu_controller_pooling_store_to_fifo_d[1:PIPELINEDEPTH-1] = pipelined_ocu_controller_pooling_store_to_fifo_q[0:PIPELINEDEPTH-2];
   end

   always_ff @(posedge clk, negedge rst) begin
      if(~rst) begin
         pipelined_ocu_controller_pooling_store_to_fifo_q <= '0;
      end else begin
         pipelined_ocu_controller_pooling_store_to_fifo_q <= pipelined_ocu_controller_pooling_store_to_fifo_d;
      end
   end

   always_comb begin
      pipelined_ocu_controller_alu_operand_sel_d[0] = ocu_controller_alu_operand_sel_o;
      pipelined_ocu_controller_alu_operand_sel_d[1:PIPELINEDEPTH-1] = pipelined_ocu_controller_alu_operand_sel_q[0:PIPELINEDEPTH-2];
   end

   always_ff @(posedge clk, negedge rst) begin
      if(~rst) begin
         pipelined_ocu_controller_alu_operand_sel_q <= '0;
      end else begin
         pipelined_ocu_controller_alu_operand_sel_q <= pipelined_ocu_controller_alu_operand_sel_d;
      end
   end


   ///////////////////////////////// END OCU GLUE LOGIC /////////////////////////////////

   ///////////////////////////////// WEIGHTMEMORY GLUE LOGIC /////////////////////////////////

   always_ff @(posedge clk, negedge rst) begin: external_bank_register
      if(~rst) begin
         weightmemory_external_bank_q <= '0;
      end else begin
         weightmemory_external_bank_q <= weightmem_external_bank_i;
      end
   end

   always_comb begin
      weightmemory_bank_helper = weightmem_external_bank_i;
   end

   always_comb begin
      if(weightmem_external_we_i == '1) begin
         weightmemory_enable_helper = '1;
      end else begin
         weightmemory_enable_helper = '0;
      end
   end
   assign __weightmemory_write_enable = (weightmemory_write_enable & weightmemory_enable_helper);

   ///////////////////////////////// END WEIGHTMEMORY GLUE LOGIC /////////////////////////////////

   ///////////////////////////////// OUTPUT ASSIGNMENT /////////////////////////////////

   assign weightmem_external_weights_o = weightmemory_external_weights_vector[weightmemory_external_bank_q];
   assign weightmem_external_valid_o = weightmemory_external_valid_vector[weightmemory_external_bank_q];
   assign compute_done_o = LUCA_compute_done_o;

   ///////////////////////////////// END OUTPUT ASSIGNMENTS /////////////////////////////////

endmodule
