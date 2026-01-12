#!/bin/sh

set -xe
source ../ci-lib.sh

# 1) Pull source and gen build environment
gen_build_dir_with_git 'https://github.com/mpi4py/mpi4py'
setup_build_env

# 2) Set mpi4py configuration
export CC='mpicc'
export CXX='mpicxx'

# 3) Build
build_bdist_wheel 'mpi4py'

# 4) Cleanup
archive_artifacts 'mpi4py'
cleanup_build_dir
