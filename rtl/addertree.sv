// ----------------------------------------------------------------------
//
// File: addertree.sv
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

module addertree
  #(
    parameter int unsigned N = 512,

    parameter int unsigned TREEWIDTH = 1536,
    parameter int unsigned BRANCHNUM = (N + TREEWIDTH-1)/TREEWIDTH,
    parameter int unsigned REM = (N)%TREEWIDTH
    )
   (
    input logic [N-1:0]        in_i,
    output logic [$clog2(N):0] popc_o
    );

   logic [BRANCHNUM-1:0][$clog2(TREEWIDTH):0] partial_sums;
   logic [BRANCHNUM-1:0][TREEWIDTH-1:0]       partial_bitvec;

   always_comb begin
      popc_o = '0;
      partial_bitvec = in_i;

      for (int i=0; i<BRANCHNUM; i++) begin
         popc_o += partial_sums[i];
      end
   end

   genvar                                    n,k;
   generate
      for (n=0; n<BRANCHNUM-1; n++ ) begin
         popcount
             #(
               .N(TREEWIDTH))
         popc_i(
                .in_i(partial_bitvec[n]),
                .popc_o(partial_sums[n])
                );

      end // for (n=0; n<BRANCHNUM; n++ )
      if (REM != 0) begin

         logic [$clog2(REM):0] partial_rem_sums;

         assign partial_sums[BRANCHNUM-1] = partial_rem_sums;

         popcount
           #(
             .N(REM))
         popc_i(
                .in_i(partial_bitvec[BRANCHNUM-1][REM-1:0]),
                .popc_o(partial_rem_sums)
                );


      end else begin // if (REM != 0)
         popcount
           #(
             .N(TREEWIDTH))
         popc_i(
                .in_i(partial_bitvec[BRANCHNUM-1][TREEWIDTH-1:0]),
                .popc_o(partial_sums[BRANCHNUM-1])
                );

      end

   endgenerate


endmodule: addertree
