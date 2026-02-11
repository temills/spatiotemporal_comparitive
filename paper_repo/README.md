# Spatiotemporal program learning in human adults, children, and monkeys
This repository contains the data, models, and analyses used to study how human adults, human children aged 3-7, and rhesus macaques make predictions about spatiotemporal sequences.


## Repository Structure

- `data/`
  - `participants/` – Human and monkey prediction data
  - `models/` – Computational model prediction data
  - `NeurIPS_data/` – Human adult and model data from Mills, T., Tenenbaum, J., & Cheyette, S. (2023).
- `human_experiment/`
  - `app` - Flask app containing human experiment
- `computational_models/`
  - `LoT` - Language of Thought program learning model
  - `Comp_GP` - Compositional Gaussian Process model, adapted from Saad et al. (2023)
  - `GP` - Gaussian Process model, adapted from Saad et al. (2023)
  - `Linear` - Local linear extrapolation model
  - `Linear_or_prev` - Local linear and previous point mixture model
  - `Polynomial` - Bayesian Polynomial Ridge Regression model
- `analysis/`
  - `preprocessed_data/`
    - `inferred_accuracy` - Posterior mean estimates of participant inferred accuracy
    - `model_likelihoods` - Likelihoods and parameter fits for participant data under each computational model
  - `stan_models` - Stan model for inferred accuracy analysis
  - `compute_inferred_accuracy.Rmd` - Inferred accuracy analysis
  - `compute_model_likelihoods_preprocessing.Rmd` - Preprocessing for model parameter fitting and likelihood estimation
  - `compute_model_likelihoods.py` - Model parameter fitting and likelihood estimation
  - `model_based_analyses.Rmd` - Analysis of participant data using computational models
  - `main_analyses.Rmd` - Model-free analysis of participant data
- `figs/` - Generated figures
- `README.md` – Project overview


## Instructions

To reproduce main results and figures, run `main_analyses.Rmd` and `model_based_analyses.Rmd` in `analysis/`.

To re-run likelihood analyses for estimating participant accuracy and model fits:
```bash
cd analysis
./run_preprocessing.sh
```

To run the computational models:
```bash
cd computational_models
./run_model.sh <model> <output_dir> <n_mcmc_iter> <n_smc_particles>
```

To run the human experiment locally (with Flask):
```bash
cd human_experiment
./run_app.sh
```

## References

Mills, T., Tenenbaum, J., & Cheyette, S. (2023). Human spatiotemporal pattern learning as probabilistic program synthesis. Advances in Neural Information Processing Systems, 36.

Saad F.A., Patton B.J., Hoffmann M.D., Saurous R.A., Mansinghka V.K. (2023). Sequential monte carlo learning for time series structure discovery. In International Conference on Machine Learning. PMLR.