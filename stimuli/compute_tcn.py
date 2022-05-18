# ----------------------------------------------------------------------
#
# File: compute_tcn.py
#
# Last edited: 05.05.2022
#
# Copyright (C) 2022, ETH Zurich and University of Bologna.
#
# Author: Tim Fischer, ETH Zurich
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

# This module generates system level stimuli and expected responses based on randomly
# generated pyTorch networks.

import numpy as np
import torch
import torch.nn as nn

np.random.seed(69)
torch.manual_seed(42)

import numpy as np
import matplotlib.pyplot as plt
from collections import namedtuple, OrderedDict
from tqdm import tqdm

from utils import *

import gen_activationmemory_full_stimuli as actmemory
import gen_weightmemory_full_stimuli as weightmemory
import gen_ocu_pool_weights_stimuli as ocu
import gen_LUCA_stimuli as LUCA

filename = 'compute_output'

name_stimuli = 'compute_output_stimuli.txt'
name_exp = 'compute_output_exp_responses.txt'

f = open(name_stimuli, 'w+')
g = open(name_exp, 'w+')

dep = open('../conf/cutie_config.py', 'r').read()
exec(dep)

numbanks = int(k * weight_stagger)

totnumtrits = imagewidth * imageheight * ni
tritsperbank = int(np.ceil(totnumtrits / numbanks))

effectivetritsperword = int(ni / weight_stagger)
physicaltritsperword = int(np.ceil(effectivetritsperword / 5)) * 5
physicalbitsperword = int(physicaltritsperword / 5 * 8)
excessbits = (physicaltritsperword - effectivetritsperword) * 2
effectivewordwidth = physicalbitsperword - excessbits
numdecoders = int(physicalbitsperword / 8)

bankdepth = int(np.ceil(tritsperbank / effectivetritsperword))

bankaddressdepth = int(np.ceil(np.log2(bankdepth)))

leftshiftbitwidth = int(np.ceil(np.log2(numbanks)))
splitbitwidth = int(np.ceil(np.log2(weight_stagger))) + 1

nibitwidth = int(np.maximum(np.ceil(np.log2(ni)), 1)) + 1
nobitwidth = int(np.maximum(np.ceil(np.log2(no)), 1))
imagewidthbitwidth = int(np.maximum(np.ceil(np.log2(imagewidth)), 1)) + 1
imageheightbitwidth = int(np.maximum(np.ceil(np.log2(imageheight)), 1)) + 1

numaddresses = int(numbanks * bankdepth)
memaddressbitwidth = int(np.maximum(np.ceil(np.log2(numaddresses)), 1))

leftshiftbitwidth = int(np.ceil(np.log2(numbanks)))
splitbitwidth = int(np.ceil(np.log2(weight_stagger))) + 1

rowaddresswidth = int(np.ceil(np.log2(imw)))
coladdresswidth = int(np.ceil(np.log2(imagewidth)))
tcnwidthaddrwidth = int(np.ceil(np.log2(tcn_width)))

matrixaddresswidth = int(np.ceil(np.log2(imageheight * imagewidth))) + 1
kaddresswidth = int(np.ceil(np.log2(k)))

_output = namedtuple("_outputs", "actmemory_external_acts_o")
_input = namedtuple("_inputs",
                    "actmemory_external_bank_set actmemory_external_we actmemory_external_req actmemory_external_addr actmemory_external_wdata weightmemory_external_bank weightmemory_external_we weightmemory_external_req weightmemory_external_addr weightmemory_external_wdata ocu_thresh_pos ocu_thresh_neg ocu_thresholds_save_enable LUCA_store_to_fifo LUCA_testmode LUCA_imagewidth LUCA_imageheight LUCA_k LUCA_ni LUCA_no LUCA_stride_width LUCA_stride_height LUCA_padding_type LUCA_pooling_enable LUCA_pooling_pooling_type LUCA_pooling_kernel LUCA_pooling_padding_type LUCA_layer_skip_in LUCA_layer_skip_out LUCA_layer_is_tcn LUCA_layer_tcn_width_mod_dil LUCA_layer_tcn_k LUCA_compute_disable")

outputtypes = _output("unsigned")
inputtypes = _input(actmemory.inputtypes.external_bank_set, actmemory.inputtypes.external_we,
                    actmemory.inputtypes.external_req, actmemory.inputtypes.external_addr,
                    actmemory.inputtypes.external_wdata, "unsigned", weightmemory.inputtypes.external_we,
                    weightmemory.inputtypes.external_req, weightmemory.inputtypes.external_addr,
                    weightmemory.inputtypes.external_wdata, ocu.inputtypes.thresh_pos, ocu.inputtypes.thresh_neg,
                    ocu.inputtypes.threshold_store_to_fifo, LUCA.inputtypes.store_to_fifo, LUCA.inputtypes.testmode,
                    LUCA.inputtypes.imagewidth, LUCA.inputtypes.imageheight, LUCA.inputtypes.k, LUCA.inputtypes.ni,
                    LUCA.inputtypes.no, LUCA.inputtypes.stride_width, LUCA.inputtypes.stride_height,
                    LUCA.inputtypes.padding_type, LUCA.inputtypes.pooling_enable, LUCA.inputtypes.pooling_pooling_type,
                    LUCA.inputtypes.pooling_kernel, LUCA.inputtypes.pooling_padding_type, LUCA.inputtypes.skip_in,
                    LUCA.inputtypes.skip_out, "unsigned", "unsigned", "unsigned", LUCA.inputtypes.compute_disable)

outputwidths = _output((physicalbitsperword, (1)))
inputwidths = _input(actmemory.inputwidths.external_bank_set, actmemory.inputwidths.external_we,
                     actmemory.inputwidths.external_req, actmemory.inputwidths.external_addr,
                     actmemory.inputwidths.external_wdata, (nobitwidth, 1), weightmemory.inputwidths.external_we,
                     weightmemory.inputwidths.external_req, weightmemory.inputwidths.external_addr,
                     weightmemory.inputwidths.external_wdata, ocu.inputwidths.thresh_pos, ocu.inputwidths.thresh_neg,
                     ocu.inputwidths.threshold_store_to_fifo, LUCA.inputwidths.store_to_fifo, LUCA.inputwidths.testmode,
                     LUCA.inputwidths.imagewidth, LUCA.inputwidths.imageheight, LUCA.inputwidths.k, LUCA.inputwidths.ni,
                     LUCA.inputwidths.no, LUCA.inputwidths.stride_width, LUCA.inputwidths.stride_height,
                     LUCA.inputwidths.padding_type, LUCA.inputwidths.pooling_enable,
                     LUCA.inputwidths.pooling_pooling_type, LUCA.inputwidths.pooling_kernel,
                     LUCA.inputwidths.pooling_padding_type, LUCA.inputwidths.skip_in, LUCA.inputwidths.skip_out,
                     (1, (1)), (coladdresswidth, (1)), (kaddresswidth, (1)), LUCA.inputwidths.compute_disable)

_layer_param = namedtuple("_layer_params", "imagewidth "
                                           "imageheight "
                                           "k "
                                           "ni "
                                           "no "
                                           "stride_width "
                                           "stride_height "
                                           "padding_type "
                                           "pooling_enable "
                                           "pooling_pooling_type "
                                           "pooling_kernel "
                                           "pooling_padding_type "
                                           "skip_in "
                                           "skip_out "
                                           "is_tcn "
                                           "tcn_width "
                                           "tcn_width_mod_dil "
                                           "tcn_k ")

layer_param_types = _layer_param(imagewidth=LUCA.inputtypes.imagewidth,
                                 imageheight=LUCA.inputtypes.imageheight,
                                 k=LUCA.inputtypes.k,
                                 ni=LUCA.inputtypes.ni,
                                 no=LUCA.inputtypes.no,
                                 stride_width=LUCA.inputtypes.stride_width,
                                 stride_height=LUCA.inputtypes.stride_height,
                                 padding_type=LUCA.inputtypes.padding_type,
                                 pooling_enable=LUCA.inputtypes.pooling_enable,
                                 pooling_pooling_type=LUCA.inputtypes.pooling_pooling_type,
                                 pooling_kernel=LUCA.inputtypes.pooling_kernel,
                                 pooling_padding_type=LUCA.inputtypes.pooling_padding_type,
                                 skip_in=LUCA.inputtypes.skip_in,
                                 skip_out=LUCA.inputtypes.skip_out,
                                 is_tcn='unsigned',
                                 tcn_width='unsigned',
                                 tcn_width_mod_dil='unsigned',
                                 tcn_k='unsigned')

layer_param_widths = _layer_param(imagewidth=LUCA.inputwidths.imagewidth,
                                  imageheight=LUCA.inputwidths.imageheight,
                                  k=LUCA.inputwidths.k,
                                  ni=LUCA.inputwidths.ni,
                                  no=LUCA.inputwidths.no,
                                  stride_width=LUCA.inputwidths.stride_width,
                                  stride_height=LUCA.inputwidths.stride_height,
                                  padding_type=LUCA.inputwidths.padding_type,
                                  pooling_enable=LUCA.inputwidths.pooling_enable,
                                  pooling_pooling_type=LUCA.inputwidths.pooling_pooling_type,
                                  pooling_kernel=LUCA.inputwidths.pooling_kernel,
                                  pooling_padding_type=LUCA.inputwidths.pooling_padding_type,
                                  skip_in=LUCA.inputwidths.skip_in,
                                  skip_out=LUCA.inputwidths.skip_out,
                                  is_tcn=(1, (1)),
                                  tcn_width=(tcnwidthaddrwidth, (1)),
                                  tcn_width_mod_dil=(tcnwidthaddrwidth, (1)),
                                  tcn_k=(kaddresswidth, (1)))

_weightmem_writes = namedtuple("_weightmem_writes", "addr bank wdata")
weightmem_writes_types = _weightmem_writes(addr='unsigned',
                                           bank='unsigned',
                                           wdata='unsigned')
weightmem_writes_widths = _weightmem_writes(addr=weightmemory.inputwidths.external_addr,
                                            bank=(nobitwidth, 1),
                                            wdata=weightmemory.inputwidths.external_wdata)

_thresholds = namedtuple("_thresholds", "pos neg we")
thresholds_types = _thresholds(pos='signed',
                               neg='signed',
                               we='unsigned')
thresholds_widths = _thresholds(pos=ocu.inputwidths.thresh_pos,
                                neg=ocu.inputwidths.thresh_neg,
                                we=ocu.inputwidths.threshold_store_to_fifo)

Thresholds = namedtuple('Thresholds', 'lo hi')

cyclenum = 0

pipelinedelay = 1
widthcounter = 0
heightcounter = 0
counting = 1

codebook, origcodebook = gen_codebook()
reverse_codebook = {}

for x, y in codebook.items():
    if y not in reverse_codebook:
        reverse_codebook[y] = x

def format_output(output):
    string = ''

    for i in range(output.shape[0]):
        for k in range(output.shape[2]):
            for l in range(output.shape[3]):
                for j in range(output.shape[1]):
                    string += (format_ternary(output[i][j][k][l])) + ' '
                string = ''

def get_thresholds(conv_node, bn_node):
    beta_hat = (conv_node.bias - bn_node.running_mean) / torch.sqrt(bn_node.running_var + bn_node.eps)
    gamma_hat = 1 / torch.sqrt(bn_node.running_var + bn_node.eps)
    beta_hat = beta_hat * bn_node.weight + bn_node.bias
    gamma_hat = gamma_hat * bn_node.weight

    thresh_high = (0.5 - beta_hat) / gamma_hat
    thresh_low = (-0.5 - beta_hat) / gamma_hat

    flip_idxs = gamma_hat < 0
    thresh_high[flip_idxs] *= -1
    thresh_low[flip_idxs] *= -1
    thresh_high = torch.ceil(thresh_high)
    thresh_low = torch.ceil(thresh_low)
    thresh_low = torch.where(torch.eq(thresh_low, -0.), torch.zeros_like(thresh_low), thresh_low)
    thresh_high = torch.where(torch.eq(thresh_high, -0.), torch.zeros_like(thresh_high), thresh_high)
    return Thresholds(thresh_low, thresh_high)

def double_threshold(x, xmin, xmax):
    if x.ndim == 4:
        xmin = xmin.unsqueeze(-1).unsqueeze(-1)
        xmax = xmax.unsqueeze(-1).unsqueeze(-1)
    elif x.ndim == 3:
        xmax = xmax.unsqueeze(-1)
        xmin = xmin.unsqueeze(-1)

    max_t = torch.gt(x, xmax)
    min_t = torch.gt(-x, -xmin) * (-1)

    return (max_t + min_t).float()

class DensetoConv(nn.Module):
    def __init__(self, input_shape, n_classes):
        self.n_classes = n_classes
        self.input_shape = input_shape
        self.n_inputs = int(np.prod(list(input_shape[1:])))
        self.conv_channels = int(np.ceil((self.n_inputs // (k ** 2)) / (ni // weight_stagger)) * ni // weight_stagger)
        with torch.no_grad():
            super(DensetoConv, self).__init__()
            self.dense = nn.Linear(self.n_inputs, out_features=n_classes)
            self.dense.weight.copy_(torch.randint_like(self.dense.weight, low=-1, high=2))
            self.dense.bias.copy_(torch.zeros_like(self.dense.bias))
            self.thresh = Thresholds(0., 0.)
            self.conv = nn.Conv2d(in_channels=self.conv_channels,
                                  out_channels=n_classes,
                                  kernel_size=k,
                                  bias=False)
            self.conv.weight.copy_(self.weights_to_conv(weights=self.dense.weight))
            self.conv.weight.requires_grad = False

    def acts_to_conv(self, acts):
        conv_acts = torch.zeros(1, self.conv_channels, k, k)

        print('acts', acts.shape, 'reshaped to', conv_acts.shape)
        for i in range(acts.shape[1]):
            n_pixels = self.input_shape[2] * self.input_shape[3]
            x = (i % n_pixels) % k
            y = (i % n_pixels) // k
            c = i // (n_pixels)
            conv_acts[0][c][y][x] = acts[0][i]
        return conv_acts

    def weights_to_conv(self, weights):
        conv_weights = torch.zeros(self.n_classes, self.conv_channels, k, k)

        print('weights', weights.shape, 'reshaped to', conv_weights.shape)
        for o in range(self.n_classes):
            for i in range(weights.shape[1]):
                n_pixels = self.input_shape[2] * self.input_shape[3]
                x = (i % n_pixels) % k
                y = (i % n_pixels) // k
                c = i // (n_pixels)
                conv_weights[o][c][y][x] = weights[o][i]
        return conv_weights

    def forward(self, x):
        y = self.conv(self.acts_to_conv(x))
        x = self.dense(x)
        assert torch.equal(y.squeeze(), x.squeeze())
        return x

class Net(nn.Module):
    def __init__(self, num_cnn_layers, num_tcn_layers, layer_no, layer_ni, n_classes, layer_k, strideh, stridew,
                 layer_padding, pooling_enable, pooling_type, pooling_kernel, pooling_padding_type, tcn_k, tcn_dilation,
                 tcn_width, imagewidth, imageheight):
        super(Net, self).__init__()
        self.cnns = nn.ModuleList()
        self.tcns = nn.ModuleList()
        self.dense = None
        self.tcn_sequence = None
        self.cnn_thresh = []
        self.tcn_thresh = []

        # CNN Layers
        for i in range(num_cnn_layers):
            with torch.no_grad():
                # Convolution
                conv = nn.Conv2d(in_channels=layer_ni[i],
                                 out_channels=layer_no[i],
                                 padding=(layer_k - 1) // 2 * layer_padding,
                                 kernel_size=layer_k,
                                 stride=(strideh[i], stridew[i]))

                conv.weight.copy_(torch.randint_like(conv.weight, low=-1, high=2))  # weights have to be ternarized
                conv.bias.copy_(
                    torch.randn_like(conv.bias))  # bias can be full precision, is integrated into thresholds
                conv.weight.requires_grad = False
                # Batch Normalization
                bn = nn.BatchNorm2d(num_features=layer_no[i])
                bn.weight.copy_(torch.randn_like(bn.weight))
                bn.bias.copy_(torch.randn_like(bn.bias))
                bn.running_mean.copy_(torch.randn_like(bn.running_mean))
                bn.running_var.copy_(torch.rand_like(bn.running_var))  # var must be positive, thus var ~ U(0,1)
                # Pooling
                if pooling_enable[i]:
                    pool = pooling_type[i](kernel_size=pooling_kernel[i], padding=pooling_padding_type[i])
                else:
                    pool = nn.Identity()
                # Thresholds
                # Flip weights where BN-gamma is negative
                conv.weight[bn.weight < 0] *= -1
                # get thresholds of layer
                self.cnn_thresh.append(get_thresholds(conv_node=conv, bn_node=bn))
                # zero bias of conv again, because bias is now integrated into threshold
                conv.bias.copy_(torch.zeros_like(conv.bias))
                self.cnns.append(nn.Sequential(OrderedDict([('conv', conv), ('bn', bn), ('pool', pool)])))

        # TCN Layers
        for i in range(num_tcn_layers):
            with torch.no_grad():
                self.tcn_sequence = torch.zeros((1, layer_ni[num_cnn_layers + i], tcn_width))
                # Left Padding
                padding = nn.ConstantPad1d(padding=((tcn_k[i] - 1) * tcn_dilation[i], 0), value=0.)
                # Convolution
                conv = nn.Conv1d(in_channels=layer_ni[num_cnn_layers + i],
                                 out_channels=layer_no[num_cnn_layers + i],
                                 kernel_size=tcn_k[i],
                                 dilation=tcn_dilation[i])
                conv.weight.copy_(torch.randint_like(conv.weight, low=-1, high=2))  # weights have to be ternarized
                conv.bias.copy_(
                    torch.randn_like(conv.bias))  # bias can be full precision, is integrated into thresholds
                conv.weight.requires_grad = False
                # Batch Normalization
                bn = nn.BatchNorm1d(num_features=layer_no[num_cnn_layers + i])
                bn.weight.copy_(torch.randn_like(bn.weight))
                bn.bias.copy_(torch.randn_like(bn.bias))
                bn.running_mean.copy_(torch.randn_like(bn.running_mean))
                bn.running_var.copy_(torch.rand_like(bn.running_var))  # var must be positive, thus var ~ U(0,1)
                # Thresholds
                # Flip weights where BN-gamma is negative
                conv.weight[bn.weight < 0] *= -1
                # get thresholds of layer
                self.tcn_thresh.append(get_thresholds(conv_node=conv, bn_node=bn))
                # zero bias of conv again, because bias is now integrated into threshold
                conv.bias.copy_(torch.zeros_like(conv.bias))
                self.tcns.append(nn.Sequential(OrderedDict([('pad', padding), ('conv', conv), ('bn', bn)])))

        # Dense Layer
        if num_dense_layers == 1:
            x = torch.zeros(1, layer_ni[0], imagewidth, imageheight)
            for i in self.cnns:
                x = i(x)
            for i in self.tcns:
                x = i(x)
            self.dense = DensetoConv(x.shape, n_classes)

        print(self)

    def forward(self, x):
        shapes = [x.shape]

        # CNN forward
        for cnn, thresh in zip(self.cnns, self.cnn_thresh):
            # I am abusing batch size as tcn_width
            x = cnn.conv(x)
            x = cnn.pool(x)
            x = double_threshold(x, xmin=thresh.lo, xmax=thresh.hi)
            shapes.append(x.shape)

        # TCN forward
        if self.tcns:
            # input shape to TCN is (1, channels, width, height)
            # -> reshape it to (channels)

            x = torch.flatten(x, start_dim=1).squeeze()
            self.tcn_sequence[:,:,:-1] = self.tcn_sequence[:,:,1:].clone()
            self.tcn_sequence[:,:,-1] = x
            x = self.tcn_sequence
            shapes[-1] = x.shape
            for tcn, thresh in zip(self.tcns, self.tcn_thresh):
                x = tcn.pad(x)
                x = tcn.conv(x)
                x = double_threshold(x, xmin=thresh.lo, xmax=thresh.hi)
                shapes.append(x.shape)

        # Dense forward
        if self.dense:
            x = torch.flatten(x, start_dim=1)
            shapes[-1] = x.shape
            x = self.dense(x)
            # x = double_threshold(x, self.dense.thresh.lo, self.dense.thresh.hi)
            shapes.append(x.shape)
            x = x.unsqueeze(-1)
        return x, shapes

    def reset(self):
        if self.tcn_sequence:
            self.tcn_sequence = torch.zeros_like(self.tcn_sequence)


def make_random_image(imagewidth, imageheight, layer_ni, rounded_ni):
    zero_pad_image = torch.zeros((1, rounded_ni, imagewidth, imageheight))
    actual_image = torch.randint(-1, 2, (1, layer_ni, imagewidth, imageheight), dtype=torch.float32)
    zero_pad_image[0, :layer_ni] = actual_image
    return actual_image, zero_pad_image

def make_random_tcn_sequence(net, layer_ni, rounded_ni, length):
    testsequence = np.zeros((1, rounded_ni, length, 1))
    testsequence[0,:layer_ni,:,0] = np.random.randint(-1, 2, (layer_ni, length))
    return testsequence

def translate_tcn_weights_to_cnn_weights(weights):
    weights2D = np.zeros((*weights.shape[:2], k, k))
    weights2D[:,:,:weights.shape[2], (k-1)//2] = weights
    return weights2D

def translate_weights_to_weightmem(weights):
    n_o, n_i, k1, k2 = weights.shape
    rounded_no = int(np.ceil(n_o / effectivetritsperword) * effectivetritsperword)
    rounded_ni = int(np.ceil(n_i / effectivetritsperword) * effectivetritsperword)

    zero_padded_weights = np.zeros((rounded_no, rounded_ni, k1, k2))
    zero_padded_weights[:n_o, :n_i] = weights

    weights = zero_padded_weights

    weightmem = np.empty((int(np.prod(weights.shape) / (ni / weight_stagger)), physicalbitsperword), dtype=int)
    weightmem_decoded = np.empty((int(np.prod(weights.shape) / (ni / weight_stagger)), effectivetritsperword*2), dtype=int)
    weightmemlist, weightmemlist_decoded = [], []
    for i in range(weights.shape[0]):
        for n in range(int(weights.shape[1] / int(ni / weight_stagger))):
            for m in range(weights.shape[3]):
                for j in range(weights.shape[2]):
                    word = np.empty(int(ni / weight_stagger))
                    for q in range(int(ni / weight_stagger)):
                        word[q] = weights[i][n * int(ni / weight_stagger) + q][j][m]
                    _word, word_decoded = translate_ternary_sequence(word)
                    weightmemlist_decoded.append(translate_binary_string(word_decoded))
                    weightmemlist.append(translate_binary_string(_word))
    weightmemarray = np.asarray(weightmemlist)
    weightmemarray_decoded = np.asarray(weightmemlist_decoded)
    weightmem = weightmemarray.reshape((int(np.prod(weights.shape) / (ni / weight_stagger)), physicalbitsperword))
    return weightmem, weightmemarray_decoded

def translate_image_to_actmem(image):
    actmem = np.empty(
        (int(np.ceil((image.shape[1]) / weight_stagger)) * image.shape[2] * image.shape[3], physicalbitsperword),
        dtype=int)
    actmemlist, actmemlist_decoded = [], []

    for n in range(image.shape[2]):
        for m in range(image.shape[3]):
            for j in range(int(np.ceil((image.shape[1]) / (ni / weight_stagger)))):
                word = np.empty(int(ni / weight_stagger))
                for i in range(int(ni / weight_stagger)):
                    word[i] = image[0][i + j * int((ni / weight_stagger))][n][m]
                _word, word_decoded = translate_ternary_sequence(word)
                actmemlist.append(translate_binary_string(_word))
                actmemlist_decoded.append(translate_binary_string(word_decoded))
    actmemarray = np.asarray(actmemlist)
    actmemarray_decoded = np.asarray(actmemlist_decoded)
    actmem = actmemarray.reshape((-1, physicalbitsperword))

    return actmem, actmemarray_decoded

def translate_binary_string(string):
    ret = np.empty(len(string), dtype=int)
    for i in range(len(string)):
        ret[i] = string[i]

    return (ret)

def translate_ternary_sequence(seq):
    string = ''
    _seq = np.copy(seq.reshape(-1))

    for i in range(len(_seq)):
        if (int(_seq[i]) == 1):
            string += "01"
        elif (int(_seq[i]) == -1):
            string += "11"
        else:
            string += "00"

    string_decoded = string
    string += "0" * (10 - (len(string)%10))
    _string = ''
    for i in range(0, int(len(string)), 10):
        substr = string[i:i + 10]
        try:
            _string += reverse_codebook[substr]
        except:
            import IPython; IPython.embed()

    return _string, string_decoded

if __name__ == '__main__':

    num_cnn_layers = 1
    num_tcn_layers = 0
    num_dense_layers = 0
    num_layers = num_cnn_layers + num_tcn_layers + num_dense_layers
    num_execs = 1

    input_imagewidth = 32
    input_imageheight = 32

    layer_channels = [ni, ni]
    n_classes = 48
    layer_ni = layer_channels[:-1]
    layer_no = layer_channels[1:]
    layer_stridew = [1, 1, 1, 1, 1]
    layer_strideh = [1, 1, 1, 1, 1]
    layer_k = 3
    layer_padding = 1

    layer_pooling_enable = [False, False, False, False, False]
    layer_pooling_type = [nn.MaxPool2d, nn.MaxPool2d, nn.MaxPool2d, nn.MaxPool2d, nn.MaxPool2d, nn.MaxPool2d, nn.MaxPool2d, nn.MaxPool2d]
    layer_pooling_padding_type = [0, 0, 0, 0, 0, 0, 0, 0]
    layer_pooling_kernel = [2, 2, 2, 2, 2, 2, 2, 2]

    layer_tcn_width = 1
    layer_tcn_dilation = [1, 2, 4]
    layer_tcn_k = [2, 2, 2]

    assert len(layer_channels) == num_layers + 1
    assert len(layer_strideh) >= num_cnn_layers
    assert len(layer_stridew) >= num_cnn_layers
    assert len(layer_tcn_k) >= num_tcn_layers
    assert len(layer_tcn_dilation) >= num_tcn_layers
    assert len(layer_pooling_enable) >= num_cnn_layers
    if num_tcn_layers == 0:
        assert layer_tcn_width == 1


    rounded_no = [int(np.ceil(n / (ni // weight_stagger)) * ni // weight_stagger) for n in layer_no]
    rounded_ni = [int(np.ceil(n / (ni // weight_stagger)) * ni // weight_stagger) for n in layer_ni]



    net = Net(num_cnn_layers, num_tcn_layers, layer_no, layer_ni, n_classes, layer_k, layer_strideh, layer_stridew,
              layer_padding, layer_pooling_enable, layer_pooling_type, layer_pooling_kernel, layer_pooling_padding_type,
              layer_tcn_k, layer_tcn_dilation, layer_tcn_width, input_imagewidth, input_imageheight)

    image, padded_image = make_random_image(input_imagewidth, input_imageheight, layer_ni[0], rounded_ni[0])

    actmem = translate_image_to_actmem(padded_image)

    weightmem_layers, weightmem_layers_decoded = [], []
    for i in range(num_cnn_layers):
        weightmem_layer, weightmem_layer_decoded = translate_weights_to_weightmem(net.cnns[i].conv.weight)
        weightmem_layers.append(weightmem_layer)
        weightmem_layers_decoded.append(weightmem_layer_decoded)
    for i in range(num_tcn_layers):
        weightmem_layer, weightmem_layer_decoded = translate_weights_to_weightmem(translate_tcn_weights_to_cnn_weights(net.tcns[i].conv.weight))
        weightmem_layers.append(weightmem_layer)
        weightmem_layers_decoded.append(weightmem_layer_decoded)
    for i in range(num_dense_layers):
        weightmem_layer, weightmem_layer_decoded = translate_weights_to_weightmem(net.dense.conv.weight)
        weightmem_layers.append(weightmem_layer)
        weightmem_layers_decoded.append(weightmem_layer_decoded)

    weightmem, weightmem_decoded = np.concatenate(weightmem_layers), np.concatenate(weightmem_layers_decoded)

    dummy_input = torch.zeros((1, layer_ni[0], input_imagewidth, input_imageheight))
    result, outshapes = net(dummy_input)
    net.reset()

    for i in outshapes:
        print(i)

    num_responses = np.prod(outshapes[-1][-2:])*rounded_no[-1]/(no//weight_stagger)
    num_acts = np.prod(outshapes[0][-2:])*rounded_no[0]/(no//weight_stagger)
    f_test_params = open("test_params.txt", 'w+')
    f_test_params.write("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n" % (num_execs, input_imagewidth, input_imageheight, rounded_ni[0], num_acts, num_responses, num_layers % 2, num_layers, num_cnn_layers, num_tcn_layers))
    f_test_params.close()

    weightmemorywrites = 0
    threshold_writes = 0
    memwrites = []
    actmemorywrites = int(np.ceil(layer_ni[0] / (ni / weight_stagger)) * input_imagewidth * input_imageheight)
    for i in range(num_layers):
        weightmemorywrites += int(np.ceil(layer_ni[i] / (ni / weight_stagger)) * layer_k * layer_k * layer_no[i])
        threshold_writes += layer_no[i]
        memwrites.append({'layer': i, 'ni': layer_ni[i], 'no': layer_no[i], 'weight_writes': weightmemorywrites,
                          'thresh_writes': threshold_writes})
    numwrites = np.maximum(actmemorywrites, weightmemorywrites)

    for i in memwrites:
        print(i)

    current_weight_write_layer, current_thresh_write_layer = 0, 0
    thresh_addr = 0
    weightmem_counter = 0
    weightmem_depth = np.zeros(no, dtype=int)
    weightmem_show = np.zeros((no, ni // (ni // weight_stagger) * k * k * 8))

    print("Generating layer params stimuli file...")
    f_layer_param = open("layer_params.txt", 'w+')
    f_layer_param_intf = open("layer_params_intf.txt", 'w+')
    for i in range(num_layers):
        #CNN Layers
        if (i < num_cnn_layers):
            b, c, h, w = outshapes[i]
            imagewidth = h
            imageheight = w
            stride_height = layer_strideh[i]
            stride_width = layer_stridew[i]
            padding_type = layer_padding
            is_tcn = 0
            tcn_k = 0
            tcn_width_mod_dil = 0
            pooling_enable = int(layer_pooling_enable[i])
            pooling_type = int(layer_pooling_type[i] != nn.MaxPool2d)
            pooling_kernel = layer_pooling_kernel[i]
            pooling_padding_type = layer_pooling_padding_type[i]

        # TCN Layers
        elif i < num_layers - num_dense_layers:
            b, c, l = outshapes[i]
            is_tcn = 1
            tcn_k = layer_tcn_k[i - num_cnn_layers]
            imagewidth = layer_tcn_dilation[i - num_cnn_layers]
            imageheight = int(np.ceil(l / imagewidth)) + (tcn_k - 1)
            stride_width = 1
            stride_height = 1
            padding_type = 1
            pooling_enable=0
            pooling_type=0
            pooling_kernel=0
            pooling_padding_type=0
            tcn_width_mod_dil = l % imagewidth  # not dilation but modulo, because of longest path
            tcn_1d_width = l

        # Dense Layers
        else:
            imagewidth = layer_k
            imageheight = layer_k
            stride_height = 1
            stride_width = 1
            padding_type = 0
            is_tcn = 0
            tcn_k = 0
            tcn_width_mod_dil = 0
            pooling_enable = 0
            pooling_type = 0
            pooling_kernel = 0
            pooling_padding_type = 0

        layer_params = _layer_param(imagewidth=imagewidth,
                                    imageheight=imageheight,
                                    k=layer_k,
                                    ni=rounded_ni[i],
                                    no=rounded_no[i],
                                    stride_height=stride_height,
                                    stride_width=stride_width,
                                    padding_type=padding_type,
                                    pooling_enable=pooling_enable,
                                    pooling_pooling_type=pooling_type,
                                    pooling_kernel=pooling_kernel,
                                    pooling_padding_type=pooling_padding_type,
                                    skip_in=0,
                                    skip_out=0,
                                    is_tcn=is_tcn,
                                    tcn_width=layer_tcn_width,
                                    tcn_width_mod_dil=tcn_width_mod_dil,
                                    tcn_k=tcn_k)
        f_layer_param.write("%s \n" % format_signals(layer_params, layer_param_types, layer_param_widths))
        f_layer_param_intf.write("%s\n" % ",".join([str(j) for j in list(layer_params)]))
    f_layer_param.close()
    f_layer_param_intf.close()

    print("Generating weight stimuli file...")
    f_weightmem_writes = open('weights.txt', 'w+')
    f_weightmem_writes_intf = open('weights_intf.txt', 'w+')
    for i in range(weightmemorywrites):
        if i >= memwrites[current_weight_write_layer]['weight_writes']:
            weightmem_counter = 0
            current_weight_write_layer += 1
            weightmem_depth[:] = current_weight_write_layer * k * k * weight_stagger
            # weightmem_depth[:] = weightmem_depth[0]

        weightmemory_writedepth = int(layer_k * layer_k * np.ceil(memwrites[current_weight_write_layer]['ni'] / (ni / weight_stagger)))
        weightmemory_bank = (int(weightmem_counter / weightmemory_writedepth) % memwrites[current_weight_write_layer]['no'])
        weightmemory_addr = weightmem_depth[weightmemory_bank]
        weightmem_depth[weightmemory_bank] += 1
        weightmemory_wdata = weightmem[i]
        weightmem_show[weightmemory_bank, weightmemory_addr] = i  # current_weight_write_layer + 1
        weightmem_counter += 1
        weights = _weightmem_writes(addr=weightmemory_addr,
                                    bank=weightmemory_bank,
                                    wdata=weightmemory_wdata)
        f_weightmem_writes.write("%s \n" % format_signals(weights, weightmem_writes_types, weightmem_writes_widths))
        weight_word_string = [int("".join([str(s) for s in weightmem_decoded[i][j:j+32]]),2) for j in range(0, ni, 32)]
        f_weightmem_writes_intf.write("%d,%d,%08x,%08x,%08x\n" % (weightmemory_addr,weightmemory_bank, *weight_word_string))
    f_weightmem_writes.close()
    f_weightmem_writes_intf.close()
    # plt.matshow(weightmem_show)
    # plt.xticks([])
    # plt.yticks([])
    # plt.xlabel('Address Depth')
    # plt.ylabel('Banks')
    # plt.show()

    print("Generating thresholds stimuli file...")
    f_thresh = open("thresholds.txt", 'w+')
    f_thresh_intf = open("thresholds_intf.txt", 'w+')
    for i in range(memwrites[-1]['thresh_writes']):
        if i >= memwrites[current_thresh_write_layer]['thresh_writes']:
            current_thresh_write_layer += 1
            thresh_addr = 0
        ocu_thresholds_save_enable = np.zeros(no, dtype=int)
        ocu_thresholds_save_enable[thresh_addr] = 1
        if (current_thresh_write_layer < num_cnn_layers):
            ocu_thresh_pos = net.cnn_thresh[current_thresh_write_layer].hi[thresh_addr]
            ocu_thresh_neg = net.cnn_thresh[current_thresh_write_layer].lo[thresh_addr]
        elif current_thresh_write_layer < num_layers - num_dense_layers:
            ocu_thresh_pos = net.tcn_thresh[current_thresh_write_layer - num_cnn_layers].hi[thresh_addr]
            ocu_thresh_neg = net.tcn_thresh[current_thresh_write_layer - num_cnn_layers].lo[thresh_addr]
        else:
            ocu_thresh_pos = 0
            ocu_thresh_neg = 0
        assert ocu_thresh_pos >= ocu_thresh_neg
        thresh_addr += 1
        thresholds = _thresholds(pos=ocu_thresh_pos,
                                 neg=ocu_thresh_neg,
                                 we=ocu_thresholds_save_enable)

        f_thresh.write("%s \n" % format_signals(thresholds, thresholds_types, thresholds_widths))
        f_thresh_intf.write("%d,%d\n" % (ocu_thresh_pos, ocu_thresh_neg))
    f_thresh.close()
    f_thresh_intf.close()

    print("Generating activation and result stimuli file...")
    f_activation = open("activations.txt", 'w+')
    f_activation_intf = open("activations_intf.txt", 'w+')
    f_responses = open("responses.txt", 'w+')
    f_responses_intf = open("responses_intf.txt", 'w+')
    f_tcn_sequence = open("tcn_sequence.txt", 'w+')
    image_seq = torch.zeros((layer_tcn_width, layer_ni[0], input_imagewidth, input_imageheight))

    for i in range(num_execs):
        new_image, new_image_padded = make_random_image(input_imagewidth, input_imageheight, layer_ni[0], rounded_ni[0])

        result, _ = net(new_image)

        encoded_image, decoded_image = translate_image_to_actmem(new_image_padded)
        for addr, (enc_word, dec_word) in enumerate(zip(encoded_image, decoded_image)):
            f_activation.write("%s \n" % "".join([str(j) for j in enc_word]))
            act_word_string = [int("".join([str(s) for s in dec_word[j:j + 32]]), 2) for j in range(0, ni, 32)]
            f_activation_intf.write("%d,%08x,%08x,%08x\n" % (addr, *act_word_string))

        encoded_result, decoded_result = translate_image_to_actmem(result.unsqueeze(-1))
        for addr, (enc_word, dec_word) in enumerate(zip(encoded_result, decoded_result)):
            f_responses.write("%s \n" % "".join([str(j) for j in enc_word]))
            act_word_string = [int("".join([str(s) for s in dec_word[j:j + 32]]), 2) for j in range(0, no, 32)]
            f_responses_intf.write("%d,%08x,%08x,%08x\n" % (addr, *act_word_string))

    f_activation.close()
    f_activation_intf.close()
    f_responses.close()
    f_responses_intf.close()
    f_tcn_sequence.close()
