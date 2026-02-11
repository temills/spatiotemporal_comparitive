#!/usr/bin/env bash

# Run with run_model.sh <model_dir> <output_dir> <n_mcmc_iter> <n_smc_particles>

model=$1
output_dir=$2
n_mcmc_iter=$3
n_smc_particles=$4
stim_path="../stimuli.json"

mkdir -p $output_dir
output_dir="../${output_dir}"

cd $model || exit 1
for stim_idx in {1..24}; do
  julia -t auto run_experiment.jl $stim_path $stim_idx $n_mcmc_iter $n_smc_particles
done
bash postprocess.sh $output_dir $stim_path
