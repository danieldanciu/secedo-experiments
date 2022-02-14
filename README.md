This repository contains scripts for evaluating SECEDO, available at:
[https://github.com/ratschlab/secedo](https://github.com/ratschlab/secedo)

This repository also contains all the information needed to reproduce the experimental results in the associated [SECEDO](https://www.biorxiv.org/content/10.1101/2021.11.08.467510v3) paper.

Please follow the installation instructions in the SECEDO repository before running the experiments.

Directories:
  - breast_cancer: download instructions and scripts for preprocessing the Breast Cancer 10xGenomics data, for creating pileup files and 
    for running SECEDO on it
  - varsim: scripts for generating and running experiments on synthetic data

All scripts are written in basic bash and are using LSF to launch jobs. The scripts are readable and well-documented, and should be easy to adapt for your needs.
