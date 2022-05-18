// ----------------------------------------------------------------------
//
// File: popc.sv
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

module popcount
  #(
    parameter int unsigned N = 512
    )
   (
    input logic [N-1:0]        in_i,
    output logic [$clog2(N):0] popc_o
    );

   always_comb begin
      popc_o = 0;
      for (int i=0; i<N/2; i++) begin
         popc_o += in_i[i];
      end
      for (int i=N/2; i<N; i++) begin
         popc_o += in_i[i];
      end
   end
endmodule // popcount
