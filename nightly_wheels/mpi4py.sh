#!/bin/sh

# 5) Build mpi4py
git clone https://github.com/mpi4py/mpi4py
cd mpi4py
CC=mpicc CXX=mpicxx python setup.py bdist_wheel > "mpi4py-build-whl-$(date +%Y-%m-%d-%H%M%S).log" 2>&1
pip install dist/*.whl
cd ../
