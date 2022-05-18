# ----------------------------------------------------------------------
#
# File: cutie_config.py
#
# Last edited: 06.05.2022
#
# Copyright (C) 2022, ETH Zurich and University of Bologna.
#
# Author: Moritz Scherer, ETH Zurich
#
# ----------------------------------------------------------------------
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the License); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an AS IS BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ni = 96 # Maximum number of input channels
no = 96 # Maximum number of output channels

imagewidth = 64 # Image width for SRAM memory in activationmemory
imageheight = 64 # Image height for SRAM memory in activationmemory
tcn_width = 24

k = 3 # QUADRATIC Kernel size
layer_fifodepth = 8

imw = 3*k # Image width for tilebuffer
imh = k # Image heigth for tilebuffer
pooling_fifodepth = imagewidth/2 # Depth of pooling fifo in OCU Pool
threshold_fifodepth = layer_fifodepth

weight_stagger = 2 # Number of cycles to load one full wight buffer in OCU Pool
pipelinedepth = 2 # Number of pipelinestages

numactmemsets = 2
actmemsetsbitwidth = np.maximum(int(np.ceil(np.log2(numactmemsets))),1)
weightmemorybankdepth = layer_fifodepth*weight_stagger*k*k
number_of_stimuli = 100 # Default number of stimuli
