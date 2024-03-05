data {
  int<lower=1> N; // number of observations
  vector<lower=0, upper=1>[N] x_pred;
  vector<lower=0, upper=1>[N] y_pred;
  vector<lower=0, upper=1>[N] x_next;
  vector<lower=0, upper=1>[N] y_next;
  vector<lower=0, upper=1>[N] x_curr;
  vector<lower=0, upper=1>[N] y_curr;
  int<lower=1> n_kids; // number of subjects
  int<lower=1> kid[N]; // subj id
  int<lower=1> n_func_types; // number of function types
  int<lower=1> func_type[N]; // function type identifiers
  int<lower=1> guess_num[N]; // timepoint of guess within function
}

parameters {
  real use_true_icpt;
  vector[n_kids] use_true_icpt_kid;
  vector[n_func_types] beta_func_type;
  real beta_guess_num;
  real<lower=0> sd_true; 
  real<lower=0> sd_curr;
  real<lower=0, upper=10> sd_kid;
  simplex[2] p_rand_strategy;
  real<lower=0, upper=1> max_p;
}


model {
  use_true_icpt ~ normal(0,3);
  use_true_icpt_kid ~ normal(0, sd_kid);
  beta_guess_num ~ normal(0,3);
  beta_func_type ~ normal(0,3);

  sd_true ~ exponential(1);
  sd_curr ~ exponential(1);
  max_p ~ beta(1,1);
  p_rand_strategy ~ dirichlet(rep_vector(1,2));
  
  for (i in 1:N) {
    real p_true = max_p * inv_logit(use_true_icpt + use_true_icpt_kid[kid[i]] + beta_func_type[func_type[i]] + beta_guess_num*guess_num[i]); //could infer param for each tpt

    vector[3] log_probs;
    log_probs[1] = log(p_true) + normal_lpdf(x_pred[i] | x_next[i], sd_true) + normal_lpdf(y_pred[i] | y_next[i], sd_true);
    log_probs[2] = log((1-p_true) * p_rand_strategy[1]) + normal_lpdf(x_pred[i] | x_curr[i], sd_curr) + normal_lpdf(y_pred[i] | y_curr[i], sd_curr);
    log_probs[3] = log((1-p_true) * p_rand_strategy[2]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, 1);
    target += log_sum_exp(log_probs);
  }
}
