// ----------------------------------------------------------------------
//
// File: tb_cutie_top.sv
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

module tb_cutie_top;

   import enums_linebuffer::*;
   import enums_conv_layer::*;
   import cutie_params::*;

   parameter  T_CLK_HI   = 7.5ns;                 // set clock high time
   parameter  T_CLK_LO   = 7.5ns;                 // set clock low time
   localparam T_CLK      = T_CLK_HI + T_CLK_LO; // calculate clock period
   parameter  T_APPL_DEL = 3.75ns;                 // set stimuli application delay
   parameter  T_ACQ_DEL  = 14ns;                 // set response aquisition delay

   localparam CODE_WIDTH = 8;
   localparam TRITS_WIDTH = 10;

   parameter STIMULI_FILE   = "../stimuli/activations.txt";
   parameter LAYER_PARAMS_FILE = "../stimuli/layer_params.txt";
   parameter WEIGHTS_FILE = "../stimuli/weights.txt";
   parameter THRESH_FILE = "../stimuli/thresholds.txt";
   parameter RESPONSE_FILE  = "../stimuli/responses.txt";
   ///////////////////////////////// GLOBAL PARAMETERS /////////////////////////////////

   parameter ACTMEM_BANK_SET = 0;
   typedef enum                                        {FP_DENSE_OUTPUT, TERNARY_OUTPUT} stimuli_type_t;
   stimuli_type_t stimuli_type;

   parameter N_I = cutie_params::N_I;
   parameter N_O = cutie_params::N_O;
   parameter K = cutie_params::K;
   parameter POOLING_FIFODEPTH = cutie_params::POOLING_FIFODEPTH;
   parameter WEIGHT_STAGGER = cutie_params::WEIGHT_STAGGER;
   parameter WEIGHTBANKDEPTH = cutie_params::WEIGHTBANKDEPTH;
   parameter NUMACTMEMBANKSETS = cutie_params::NUMACTMEMBANKSETS;

   parameter int unsigned                              POOLING_USAGEWIDTH = POOLING_FIFODEPTH > 1 ? $clog2(POOLING_FIFODEPTH) : 1;
   parameter int unsigned                              THRESHOLD_USAGEWIDTH = THRESHOLD_FIFODEPTH > 1 ? $clog2(THRESHOLD_FIFODEPTH) : 1;

   parameter int unsigned                              EFFECTIVETRITSPERWORD = N_I/WEIGHT_STAGGER;
   parameter int unsigned                              PHYSICALTRITSPERWORD = ((EFFECTIVETRITSPERWORD + 4) / 5) * 5; // Round up number of trits per word; cut excess
   parameter int unsigned                              PHYSICALBITSPERWORD = PHYSICALTRITSPERWORD / 5 * 8;
   parameter int unsigned                              EXCESSBITS = (PHYSICALTRITSPERWORD - EFFECTIVETRITSPERWORD)*2;
   parameter int unsigned                              EFFECTIVEWORDWIDTH = PHYSICALBITSPERWORD - EXCESSBITS;

   parameter int unsigned                              NUMDECODERSPERBANK = PHYSICALBITSPERWORD/8;

   parameter int unsigned                              NUMBANKS = K*WEIGHT_STAGGER; // Need K*NI trits per cycle
   parameter int unsigned                              TOTNUMTRITS = IMAGEWIDTH*IMAGEHEIGHT*N_I;
   parameter int unsigned                              TRITSPERBANK = (TOTNUMTRITS+NUMBANKS-1)/NUMBANKS;
   parameter int unsigned                              ACTMEMBANKDEPTH = (TRITSPERBANK+EFFECTIVETRITSPERWORD-1)/EFFECTIVETRITSPERWORD;

   parameter int unsigned                              LEFTSHIFTBITWIDTH = NUMBANKS > 1 ? $clog2(NUMBANKS) : 1;
   parameter int unsigned                              BANKSETSBITWIDTH = NUMACTMEMBANKSETS > 1 ? $clog2(NUMACTMEMBANKSETS) : 1;
   parameter int unsigned                              SPLITBITWIDTH = $clog2(WEIGHT_STAGGER)+1;

   parameter int unsigned                              WEIGHTMEMFULLADDRESSBITWIDTH = $clog2(WEIGHTBANKDEPTH);
   parameter int unsigned                              ACTMEMFULLADDRESSBITWIDTH = $clog2(NUMBANKS*ACTMEMBANKDEPTH);

   ///////////////////////////////// GLOBAL PARAMETERS /////////////////////////////////

   typedef struct                                      packed {
      logic [PHYSICALBITSPERWORD-1:0]                  data;
   } response_t;

   typedef struct                                      packed {
      logic [PHYSICALBITSPERWORD-1:0]                  data;
   } stimuli_t;

   typedef struct                                      packed {
      logic [$clog2(K*K*N_I):0]                        actmem_external_acts_o;
   } fp_response_t;

   typedef struct                                      packed {
      logic [$clog2(IMAGEWIDTH):0]                     imagewidth;
      logic [$clog2(IMAGEHEIGHT):0]                    imageheight;
      logic [$clog2(K):0]                              k;
      logic [$clog2(N_I):0]                            ni;
      logic [$clog2(N_O):0]                            no;
      logic [$clog2(K)-1:0]                            stride_width;
      logic [$clog2(K)-1:0]                            stride_height;
      logic                                            padding_type;
      logic                                            pooling_enable;
      logic                                            pooling_pooling_type;
      logic [$clog2(K)-1:0]                            pooling_kernel;
      logic                                            pooling_padding_type;
      logic                                            skip_in;
      logic                                            skip_out;
      logic                                            is_tcn;
      logic [$clog2(TCN_WIDTH)-1:0]                    tcn_width;
      logic [$clog2(TCN_WIDTH)-1:0]                    tcn_width_mod_dil;
      logic [$clog2(K)-1:0]                            tcn_k;
   } layer_params_t;

   typedef struct                                      packed {
      logic [WEIGHTMEMFULLADDRESSBITWIDTH-1:0]         addr;
      logic [$clog2(N_O)-1:0]                          bank;
      logic [PHYSICALBITSPERWORD-1:0]                  wdata;
   } weightmem_writes_t;

   typedef struct                                      packed {
      logic [$clog2(K*K*N_I):0]                        pos;
      logic [$clog2(K*K*N_I):0]                        neg;
      logic [0:N_O-1]                                  we;
   } thresholds_t;

   //-------------------- Testbench signals --------------------
   logic                                               end_of_sim;
   logic                                               end_of_layer_transfer;
   logic                                               end_of_acq;
   logic                                               actmem_set;

   layer_params_t layer_param, layer_params[];
   weightmem_writes_t weight, weights[];
   thresholds_t threshold, thresholds[];
   stimuli_t stimuli, stimulis[];
   response_t            exp_response, exp_responses[];
   fp_response_t fp_exp_response, fp_exp_responses[];

   logic                                               clk;
   logic                                               rst;

   integer                                             error_counter;
   integer                                             total_counter;
   integer                                             enc_error_sum;
   integer                                             encoding_error_counter;
   int unsigned                                        num_words;
   int unsigned                                        num_execs;
   int unsigned                                        num_responses;

   response_t actual_response;
   response_t comp_response;

   fp_response_t fp_actual_response;
   fp_response_t fp_comp_response;

   //---------------- Signals connecting to MUT ----------------

   logic [BANKSETSBITWIDTH-1:0]                        actmem_external_bank_set_i;
   logic                                               actmem_external_we_i;
   logic                                               actmem_external_req_i;
   logic [ACTMEMFULLADDRESSBITWIDTH-1:0]               actmem_external_addr_i;
   logic [PHYSICALBITSPERWORD-1:0]                     actmem_external_wdata_i;

   logic [$clog2(N_O)-1:0]                             weightmem_external_bank_i;
   logic                                               weightmem_external_we_i;
   logic                                               weightmem_external_req_i;
   logic [WEIGHTMEMFULLADDRESSBITWIDTH-1:0]            weightmem_external_addr_i;
   logic [PHYSICALBITSPERWORD-1:0]                     weightmem_external_wdata_i;

   logic signed [$clog2(K*K*N_I):0]                    ocu_thresh_pos_i;
   logic signed [$clog2(K*K*N_I):0]                    ocu_thresh_neg_i;
   logic [0:N_O-1]                                     ocu_thresholds_save_enable_i;

   logic                                               LUCA_store_to_fifo_i;
   logic                                               LUCA_testmode_i;
   logic unsigned [$clog2(IMAGEWIDTH):0]               LUCA_layer_imagewidth_i;
   logic unsigned [$clog2(IMAGEHEIGHT):0]              LUCA_layer_imageheight_i;
   logic unsigned [$clog2(K):0]                        LUCA_layer_k_i;
   logic unsigned [$clog2(N_I):0]                      LUCA_layer_ni_i;
   logic unsigned [$clog2(N_O):0]                      LUCA_layer_no_i;
   logic unsigned [$clog2(K)-1:0]                      LUCA_layer_stride_width_i;
   logic unsigned [$clog2(K)-1:0]                      LUCA_layer_stride_height_i;
   logic                                               LUCA_layer_padding_type_i;
   logic                                               LUCA_pooling_enable_i;
   logic                                               LUCA_pooling_pooling_type_i;
   logic unsigned [$clog2(K)-1:0]                      LUCA_pooling_kernel_i;
   logic                                               LUCA_pooling_padding_type_i;
   logic                                               LUCA_layer_skip_in_i;
   logic                                               LUCA_layer_skip_out_i;
   logic                                               LUCA_layer_is_tcn_i;
   logic [$clog2(TCN_WIDTH)-1:0]                       LUCA_layer_tcn_width_i;
   logic [$clog2(TCN_WIDTH)-1:0]                       LUCA_layer_tcn_width_mod_dil_i;
   logic [$clog2(K)-1:0]                               LUCA_layer_tcn_k_i;
   logic                                               LUCA_compute_disable_i;


   logic [PHYSICALBITSPERWORD-1:0]                     actmem_external_acts_o;
   logic                                               actmem_external_valid_o;

   logic [PHYSICALBITSPERWORD-1:0]                     weightmem_external_weights_o;
   logic                                               weightmem_external_valid_o;

   logic                                               compute_done_o;
   logic [0:N_O-1][$clog2(K*K*N_I):0]                  fp_output_o;

   //--------------------- Instantiate MUT ---------------------
   cutie_top   #()
   i_mut (
          .clk_i(clk),
          .rst_ni(rst),
          .actmem_external_bank_set_i(actmem_external_bank_set_i),
          .actmem_external_we_i(actmem_external_we_i),
          .actmem_external_req_i(actmem_external_req_i),
          .actmem_external_addr_i(actmem_external_addr_i),
          .actmem_external_wdata_i(actmem_external_wdata_i),

          .weightmem_external_bank_i(weightmem_external_bank_i),
          .weightmem_external_we_i(weightmem_external_we_i),
          .weightmem_external_req_i(weightmem_external_req_i),
          .weightmem_external_addr_i(weightmem_external_addr_i),
          .weightmem_external_wdata_i(weightmem_external_wdata_i),

          .ocu_thresh_pos_i(ocu_thresh_pos_i),
          .ocu_thresh_neg_i(ocu_thresh_neg_i),
          .ocu_thresholds_save_enable_i(ocu_thresholds_save_enable_i),

          .LUCA_store_to_fifo_i(LUCA_store_to_fifo_i),
          .LUCA_testmode_i(LUCA_testmode_i),
          .LUCA_layer_imagewidth_i(LUCA_layer_imagewidth_i),
          .LUCA_layer_imageheight_i(LUCA_layer_imageheight_i),
          .LUCA_layer_k_i(LUCA_layer_k_i),
          .LUCA_layer_ni_i(LUCA_layer_ni_i),
          .LUCA_layer_no_i(LUCA_layer_no_i),
          .LUCA_layer_stride_width_i(LUCA_layer_stride_width_i),
          .LUCA_layer_stride_height_i(LUCA_layer_stride_height_i),
          .LUCA_layer_padding_type_i(LUCA_layer_padding_type_i),
          .LUCA_pooling_kernel_i(LUCA_pooling_kernel_i),
          .LUCA_pooling_enable_i(LUCA_pooling_enable_i),
          .LUCA_pooling_pooling_type_i(LUCA_pooling_pooling_type_i),
          .LUCA_pooling_padding_type_i(LUCA_pooling_padding_type_i),
          .LUCA_layer_skip_in_i(LUCA_layer_skip_in_i),
          .LUCA_layer_skip_out_i(LUCA_layer_skip_out_i),
          .LUCA_layer_is_tcn_i(LUCA_layer_is_tcn_i),
          .LUCA_layer_tcn_width_i(LUCA_layer_tcn_width_i),
          .LUCA_layer_tcn_width_mod_dil_i(LUCA_layer_tcn_width_mod_dil_i),
          .LUCA_layer_tcn_k_i(LUCA_layer_tcn_k_i),
          .LUCA_compute_disable_i(LUCA_compute_disable_i),

          .actmem_external_acts_o(actmem_external_acts_o),
          .actmem_external_valid_o(actmem_external_valid_o),
          .weightmem_external_weights_o(weightmem_external_weights_o),
          .weightmem_external_valid_o(weightmem_external_valid_o),
          .compute_done_o(compute_done_o),
          .fp_output_o(fp_output_o)
          );

   //------------------ Generate clock signal ------------------
   initial begin

      #T_CLK;
      rst = 1'b1;
      #T_CLK;
      rst = 1'b0;
      #T_CLK;
      rst = 1'b1;
      #T_CLK;

      do begin
         clk = 1'b1; #T_CLK_HI;
         clk = 1'b0; #T_CLK_LO;
      end while (end_of_sim == 1'b0);
   end // initial begin

   //------------------- Stimuli Application -------------------
   initial begin : transfer_network
      stimuli_type = TERNARY_OUTPUT;

      end_of_sim = 0;
      end_of_acq = 0;
      end_of_layer_transfer = 0;
      actmem_set = ACTMEM_BANK_SET;

      actmem_external_bank_set_i = '0;
      actmem_external_we_i = '0;
      actmem_external_req_i = '0;
      actmem_external_addr_i = '0;
      actmem_external_wdata_i = '0;

      weightmem_external_bank_i = '0;
      weightmem_external_we_i = '0;
      weightmem_external_req_i = '0;
      weightmem_external_addr_i = '0;
      weightmem_external_wdata_i = '0;

      ocu_thresh_pos_i = '0;
      ocu_thresh_neg_i = '0;
      ocu_thresholds_save_enable_i = '0;

      LUCA_compute_disable_i = 1;
      LUCA_layer_padding_type_i = '0;
      LUCA_layer_stride_height_i = '0;
      LUCA_layer_stride_width_i = '0;
      LUCA_layer_no_i = '0;
      LUCA_layer_ni_i = '0;
      LUCA_layer_k_i = '0;
      LUCA_layer_imagewidth_i = '0;
      LUCA_layer_imageheight_i = '0;
      LUCA_pooling_enable_i = '0;
      LUCA_pooling_kernel_i = '0;
      LUCA_pooling_pooling_type_i = '0;
      LUCA_pooling_padding_type_i = '0;
      LUCA_layer_skip_in_i = '0;
      LUCA_layer_skip_out_i = '0;
      LUCA_layer_is_tcn_i = '0;
      LUCA_layer_tcn_width_mod_dil_i = '0;
      LUCA_layer_tcn_k_i = '0;
      LUCA_testmode_i ='0;
      LUCA_store_to_fifo_i = '0;

      //------------------- Layer Params Transfer -------------------
      $display("Loading Layer params from %s", LAYER_PARAMS_FILE);
      $readmemb(LAYER_PARAMS_FILE, layer_params);

      num_words = (layer_params[0].imagewidth * layer_params[0].imageheight * (layer_params[0].ni / (N_I/WEIGHT_STAGGER)));

      //Apply the stimuli
      foreach(layer_params[i]) begin
         //Wait for one clock cycle
         @(posedge clk);
         //Delay application by the stimuli application delay
         #T_APPL_DEL;

         LUCA_store_to_fifo_i = 1;
         LUCA_layer_padding_type_i = layer_params[i].padding_type;
         LUCA_layer_stride_height_i = layer_params[i].stride_height;
         LUCA_layer_stride_width_i = layer_params[i].stride_width;
         LUCA_layer_no_i = layer_params[i].no;
         LUCA_layer_ni_i = layer_params[i].ni;
         LUCA_layer_k_i = layer_params[i].k;
         LUCA_layer_imagewidth_i = layer_params[i].imagewidth;
         LUCA_layer_imageheight_i = layer_params[i].imageheight;
         LUCA_pooling_enable_i = layer_params[i].pooling_enable;
         LUCA_pooling_kernel_i = layer_params[i].pooling_kernel;
         LUCA_pooling_pooling_type_i = layer_params[i].pooling_pooling_type;
         LUCA_pooling_padding_type_i = layer_params[i].pooling_padding_type;
         LUCA_layer_skip_in_i = layer_params[i].skip_in;
         LUCA_layer_skip_out_i = layer_params[i].skip_out;
         LUCA_layer_is_tcn_i = layer_params[i].is_tcn;
         LUCA_layer_tcn_width_i = layer_params[i].tcn_width;
         LUCA_layer_tcn_width_mod_dil_i = layer_params[i].tcn_width_mod_dil;
         LUCA_layer_tcn_k_i = layer_params[i].tcn_k;
         actmem_set = (actmem_set + 1) % 2;
      end // foreach (layer_params[i])

      @(posedge clk);

      #T_APPL_DEL;

      LUCA_layer_padding_type_i = '0;
      LUCA_layer_stride_height_i = '0;
      LUCA_layer_stride_width_i = '0;
      LUCA_layer_no_i = '0;
      LUCA_layer_ni_i = '0;
      LUCA_layer_k_i = '0;
      LUCA_layer_imagewidth_i = '0;
      LUCA_layer_imageheight_i = '0;
      LUCA_pooling_enable_i = '0;
      LUCA_pooling_kernel_i = '0;
      LUCA_pooling_pooling_type_i = '0;
      LUCA_pooling_padding_type_i = '0;
      LUCA_layer_skip_in_i = '0;
      LUCA_layer_skip_out_i = '0;
      LUCA_layer_is_tcn_i = '0;
      LUCA_layer_tcn_width_mod_dil_i = '0;
      LUCA_layer_tcn_k_i = '0;
      LUCA_testmode_i ='0;
      LUCA_store_to_fifo_i = '0;

      repeat(20) @(posedge clk);

      //------------------- Thresholds Transfer -------------------
      $display("Loading thresholds  from %s", THRESH_FILE);
      $readmemb(THRESH_FILE, thresholds);

      foreach(thresholds[i]) begin
         //Wait for one clock cycle
         @(posedge clk);
         //Delay application by the stimuli application delay
         #T_APPL_DEL;

         ocu_thresh_pos_i = thresholds[i].pos;
         ocu_thresh_neg_i = thresholds[i].neg;
         ocu_thresholds_save_enable_i = thresholds[i].we;
      end

      @(posedge clk);

      #T_APPL_DEL;

      ocu_thresh_pos_i = '0;
      ocu_thresh_neg_i = '0;
      ocu_thresholds_save_enable_i = '0;

      repeat(20) @(posedge clk);

      //------------------- Weights Transfer -------------------
      $display("Loading weights  from %s", WEIGHTS_FILE);
      $readmemb(WEIGHTS_FILE, weights);

      foreach(weights[i]) begin
         //Wait for one clock cycle
         @(posedge clk);
         //Delay application by the stimuli application delay
         #T_APPL_DEL;

         weightmem_external_bank_i = weights[i].bank;
         weightmem_external_we_i = 1;
         weightmem_external_req_i = 1;
         weightmem_external_addr_i = weights[i].addr;
         weightmem_external_wdata_i = weights[i].wdata;
      end

      @(posedge clk);

      #T_APPL_DEL;

      weightmem_external_bank_i = '0;
      weightmem_external_we_i = '0;
      weightmem_external_req_i = '0;
      weightmem_external_addr_i = '0;
      weightmem_external_wdata_i = '0;

      //Wait additional cycles for response acquisition to finish
      repeat(20) @(posedge clk);
      end_of_layer_transfer = 1;
   end // initial begin

   initial begin : apply_stimuli

      error_counter = 0;
      total_counter = 0;
      encoding_error_counter = 0;

      wait(end_of_layer_transfer);

      //------------------- Stimuli Transfer -------------------
      $display("Loading stimuli from %s", STIMULI_FILE);
      $readmemb(STIMULI_FILE, stimulis);
      $display("Loading responses from %s", RESPONSE_FILE);
      $readmemb(RESPONSE_FILE, exp_responses);

      num_execs = $size(stimulis) / num_words;
      num_responses = $size(exp_responses) / num_execs;

      for (int n = 0; n < num_execs; n++) begin
         $display("\nApplying stimuli and checking response, Iteration: %d", n);
         for (int i = 0; i < num_words; i++) begin

            @(posedge clk);
            #T_APPL_DEL;

            actmem_external_bank_set_i = '0;
            actmem_external_we_i = 1;
            actmem_external_req_i = 1;
            actmem_external_addr_i = i;
            actmem_external_wdata_i = stimulis[i+num_words*n];
         end // for (int i = 0; i < num_words; i++)

         @(posedge clk);
         #T_APPL_DEL;

         actmem_external_bank_set_i = '0;
         actmem_external_we_i = '0;
         actmem_external_req_i = '0;
         actmem_external_addr_i = '0;
         actmem_external_wdata_i = '0;

         repeat(20) @(posedge clk);
         #T_APPL_DEL;

         LUCA_compute_disable_i = 0;
         wait(compute_done_o);


         repeat(20) @(posedge clk);

         #T_APPL_DEL;
         LUCA_compute_disable_i = 1;

         repeat(20) @(posedge clk);
         for(int i = 0; i < num_responses; i++) begin
            @(posedge clk);
            #T_APPL_DEL;

            actmem_external_bank_set_i = actmem_set;
            actmem_external_req_i = 1;
            actmem_external_addr_i = i;

            @(posedge clk);
            #T_ACQ_DEL;
            actual_response = actmem_external_acts_o;
            assert (actmem_external_valid_o);
            exp_response = exp_responses[i+n*num_responses];

            total_counter = total_counter + 1;
            if (actual_response !== exp_response) begin
               if($countones(actual_response ^ exp_response) == 1) begin
                  encoding_error_counter += 1;
                  $display("Correct! actual: %b expected: %b \t Encoding Warning!", actual_response, exp_response);
               end else begin
                  $display("Mismatch between expected and actual response. Was %b but should be %b, number of wrong bits %d",
                           actual_response, exp_response, $countones(actual_response ^ exp_response));
                  error_counter = error_counter + 1;
               end
            end else begin
               $display("Correct! actual: %b expected: %b", actual_response, exp_response);
            end
         end // foreach (responses[i])
         actmem_external_bank_set_i = '0;
         actmem_external_req_i = '0;
         actmem_external_addr_i = '0;

         repeat(20) @(posedge clk);
      end // for (int n = 0; n < num_execs; n++)
      end_of_sim = 1;
   end

   initial begin
      wait(end_of_sim);
      $display("Tested %d stimuli", total_counter);
      if(error_counter == 0 && encoding_error_counter == 0) begin
         $display("No errors in testbench");
      end else begin
         $display("%d errors and %d encoding warnings in testbench", error_counter, encoding_error_counter);
      end
      $display("Simulation finished.");
      $finish;
   end

endmodule : tb_cutie_top
