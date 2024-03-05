data {
  int<lower=1> N; // number of observations
  vector<lower=0, upper=1>[N] x_pred;
  vector<lower=0, upper=1>[N] y_pred;
  vector<lower=0, upper=1>[N] x_next;
  vector<lower=0, upper=1>[N] y_next;
  vector<lower=0, upper=1>[N] x_curr;
  vector<lower=0, upper=1>[N] y_curr;

  int<lower=1> n_func_types; // number of function types
  int<lower=1> func_type[N]; // function type identifiers
  vector[N] n_seen; // count of function types seen
}

parameters {
  
  real use_true_icpt;

  // Effects of function type and count
  vector[n_func_types] beta_func_type;
  

  real<lower=0> sd_true; 
  real<lower=0> sd_curr;

  real beta_seen;
  vector[n_func_types] beta_func_type_seen;

  simplex[2] p_rand_strategy;
  
  real<lower=0, upper=1> max_p;

}


model {
  
  use_true_icpt ~ normal(0,3);
  beta_seen ~ normal(0,3);
  beta_func_type ~ normal(0,1);
  beta_func_type_seen ~ normal(0,1);
  sd_true ~ exponential(1);
  sd_curr ~ exponential(1);
  max_p ~ beta(1,1);

  p_rand_strategy ~ dirichlet(rep_vector(1,2));
  
  for (i in 1:N) {
   //real p_true = inv_logit(use_true_icpt + (beta_seen * n_seen[i]) + beta_func_type[func_type[i]]);
    real p_true = max_p * inv_logit(use_true_icpt + ((beta_seen + beta_func_type_seen[func_type[i]]) * n_seen[i]) + beta_func_type[func_type[i]]);

    vector[3] log_probs;
    log_probs[1] = log(p_true) + normal_lpdf(x_pred[i] | x_next[i], sd_true) + normal_lpdf(y_pred[i] | y_next[i], sd_true);
    log_probs[2] = log((1-p_true) * p_rand_strategy[1]) + normal_lpdf(x_pred[i] | x_curr[i], sd_curr) + normal_lpdf(y_pred[i] | y_curr[i], sd_curr);
    log_probs[3] = log((1-p_true) * p_rand_strategy[2]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, 1);
    
    target += log_sum_exp(log_probs);
    
  }
  
}
