data {
  int<lower=1> N; // number of observations
  vector<lower=0, upper=1>[N] x_pred;
  vector<lower=0, upper=1>[N] y_pred;
  vector<lower=0, upper=1>[N] x_next;
  vector<lower=0, upper=1>[N] y_next;
  vector<lower=0, upper=1>[N] x_curr;
  vector<lower=0, upper=1>[N] y_curr;
  vector<lower=0, upper=1>[N] x_lin;
  vector<lower=0, upper=1>[N] y_lin;
  
  real<lower=0> screen_ratio;

  int<lower=1> n_func_types; // number of function types
  int<lower=1> func_type[N]; // function type identifiers
  vector[N] n_seen; // count of function types seen
}

parameters {

  // Effects of function type and count
  vector[n_func_types] beta_func_type;
  vector[n_func_types] beta_func_type_seen;
  real<lower=0> sd_motor;
  simplex[2] p_rand_strategy[n_func_types];
}

model {

  beta_func_type ~ normal(0, 3);
  
  beta_func_type_seen ~ normal(0,1);
  sd_motor ~ exponential(1);
  p_rand_strategy ~ dirichlet(rep_vector(1,2));

  for (i in 1:N) {
    real p_true = inv_logit(beta_func_type_seen[func_type[i]] * n_seen[i] + beta_func_type[func_type[i]]);

    vector[3] log_probs;
    log_probs[1] = log(p_true) + normal_lpdf(x_pred[i] | x_next[i], sd_motor) + normal_lpdf(y_pred[i] | y_next[i], screen_ratio*sd_motor);
    log_probs[2] = log((1 - p_true) * p_rand_strategy[func_type[i]][1]) + normal_lpdf(x_pred[i] | x_curr[i], sd_motor) + normal_lpdf(y_pred[i] | y_curr[i], screen_ratio*sd_motor);
    log_probs[3] = log((1 - p_true) * p_rand_strategy[func_type[i]][2]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, 1);

    target += log_sum_exp(log_probs);
  }
}



