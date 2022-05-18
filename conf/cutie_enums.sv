// ----------------------------------------------------------------------
//
// File: cutie_enums.sv
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
// Holds enums for different modules

// OCU POOL MODULE ENUMS

package enums_ocu_pool;

   typedef enum logic [1:0]
                {POS=2'b01, ZERO=2'b00, NEG=2'b11} trit;
   typedef enum logic [1:0]
                {ALU_OPERAND_ZERO=2'b00, ALU_OPERAND_FIFO=2'b01, ALU_OPERAND_PREVIOUS=2'b10, ALU_OPERAND_MINUS_INF = 2'b11} alu_operand_sel;
   typedef enum logic
                {MULTIPLEXER_CONV=1'b0, MULTIPLEXER_ALU=1'b1} multiplexer;
   typedef enum logic
                {ALU_OP_MAX=1'b0, ALU_OP_SUM=1'b1} alu_op;

endpackage // ocu_pool

// LINEBUFFER MODULE ENUMS

package enums_linebuffer;

   typedef enum logic
                {WRAP_AROUND_ENABLE=1'b1, WRAP_AROUND_DISABLE=1'b0} wrap_around;

endpackage // linebuffer

package enums_conv_layer;
   typedef enum logic
                {SAME=1'b1, VALID=1'b0} padding_type;
endpackage // enums_conv_layer

package enums_rw_state;
   typedef enum logic [1:0]
                {NONE=2'b00, READ=2'b01, WRITE=2'b10, READ_WRITE=2'b11} rw_state;
endpackage // enums_rw_state
