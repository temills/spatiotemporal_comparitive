#!/usr/bin/env bash

output_dir=$1
stim_dir=$2

julia compute_noise_estimates.jl $stim_dir
python rescale_output.py $output_dir $stim_dir