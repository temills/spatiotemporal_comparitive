#!/usr/bin/env bash

#Rscript -e "rmarkdown::render('compute_inferred_accuracy.Rmd', output_file = tempfile(), quiet=TRUE)"
#Rscript -e "rmarkdown::render('compute_model_likelihoods_preprocessing.Rmd', output_file = tempfile(), quiet=TRUE)"
python compute_model_likelihoods.py