// ----------------------------------------------------------------------
//
// File: cutie_conf.sv
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


package cutie_params;

   parameter int unsigned N_I = 96; // # MAX. INPUT CHANNELS
   parameter int unsigned N_O = 96; // # MAX. OUTPUT CHANNELS, SHOULD EQUAL N_I

   // SYSTEM ARCHITECTURE PARAMETERS
   parameter int unsigned K = 3; // KERNEL SIZE, INTERPRETED AS QUADRATIC, I.E. (KxK)
   parameter int unsigned IMAGEWIDTH = 64; // SIZE OF THE BIGGEST IMAGE
   parameter int unsigned IMAGEHEIGHT = 64;
   parameter int unsigned TCN_WIDTH = 24;
   parameter int unsigned NUMACTMEMBANKSETS = 3; // 2 FOR DOUBLE BUFFERING, +1 FOR TCNS
   parameter int unsigned NUM_LAYERS = 8; // MAXIMUM NUMBER OF SUPPORTED LAYERS PER EXECUTION

   // HARDWARE IMPLEMENTATION PARAMETERS
   parameter int unsigned WEIGHT_STAGGER = 2; // NUMBER OF WORDS PER MAX. CHANNEL
   parameter int unsigned PIPELINEDEPTH = 2;
   parameter int unsigned WEIGHTMEMORYBANKDEPTH = NUM_LAYERS*WEIGHT_STAGGER*K*K; // NUMBER OF WORDS PER WEIGHT MEMORY BANK

   // OCU POOL PARAMETERS
   parameter int unsigned POOLING_FIFODEPTH = IMAGEWIDTH/2;
   parameter int unsigned THRESHOLD_FIFODEPTH = NUM_LAYERS;
   parameter int unsigned LAYER_FIFODEPTH = NUM_LAYERS;

   parameter int unsigned WEIGHTBANKDEPTH = NUM_LAYERS*WEIGHT_STAGGER*K*K;
   parameter int unsigned USAGEWIDTH = POOLING_FIFODEPTH > 1 ? $clog2(POOLING_FIFODEPTH) : 1;

endpackage
