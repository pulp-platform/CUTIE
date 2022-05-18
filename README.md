# CUTIE

CUTIE, the Completely Unrolled Ternary Inference Engine, is a ternary neural network accelerator targetting high-efficiency and low-power applications.
This repository contains the hardware model of CUTIE, as well as the infrastructure to test it by deploying networks to CUTIE.

## Structure

This repository is structured as follows:

- `rtl` contains the RTL code and Verilog testbench for CUTIE
- `conf` contains the implementation configuration of the accelerator
- `stimuli` contains the python-based stimuli generators for CUTIE
- `sim` contains the files required to start the simulation

## Getting started

### Dependencies

This repo uses Bender (https://github.com/pulp-platform/bender) to manage its dependencies and generate compilation scripts.
For this reason, the build process of this project will download a current version of the Bender binary.

The included simulation flow is based on a file-based testbench and a golden model implementation in PyTorch / python.
To install the required python dependencies, run
```bash
pip install -r requirements.txt
```
Generating stimuli was tested with `python 3.7`, other versions may or may not work.

Currently, Modelsim is the only supported simulation platform.

### Starting the simulation

To compile and simulate the project after installing all dependencies, you may run
```bash
make gen sim
```
which will download bender if not done already, fetch the RTL dependencies, generate random test stimuli and start ModelSim.

### Configuring the architecture

CUTIE is designed to be parametrizable in many of its fundamental aspects. If you would
like to parametrize CUTIE differently than the given example, you can edit `conf/cutie_conf.sv` and `conf/cutie_config.py`
which are the packaged parameter for the RTL implementation and stimuli generation, respectively.

Please be aware that not all combinations of parameters have been tested or are anticipated to work without changes to RTL/Stimuli generators.
The main parameters that have been ensured to be modifiable are N_I and N_O, the number of input, and output channels.

## License

CUTIE is released under permissive open source licenses. CUTIE's source code is released under the Solderpad v0.51 (`SHL-0.51`) license see [`LICENSE`](LICENSE). The code in `stimuli` is released under the Apache License 2.0 (`Apache-2.0`) see [`stimuli/LICENSE`](stimuli/LICENSE).

## Publication

If you find CUTIE useful in your research, you can cite us:

```
@InProceedings{CUTIE2022,
  author={Scherer, Moritz and Rutishauser, Georg and Cavigelli, Lukas and Benini, Luca},
  journal={IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems},
  title={CUTIE: Beyond PetaOp/s/W Ternary DNN Inference Acceleration With Better-Than-Binary Energy Efficiency},
  year={2022},
  volume={41},
  number={4},
  pages={1020-1033},
  doi={10.1109/TCAD.2021.3075420}
  }
```

This paper is also available at arXiv, at the following link: [arXiv:2011.01713 [cs.AR]](https://arxiv.org/abs/2011.01713).
