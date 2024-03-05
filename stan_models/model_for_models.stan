data {
  int<lower=1> N; // number of observations
  vector<lower=0, upper=1>[N] x_pred;
  vector<lower=0, upper=1>[N] y_pred;
  vector<lower=0, upper=1>[N] x_next;
  vector<lower=0, upper=1>[N] y_next;
  vector<lower=0, upper=1>[N] x_curr;
  vector<lower=0, upper=1>[N] y_curr;
  vector<lower=0, upper=1>[N] particle_weight; // particle weight for the given guess
  //vector<lower=0>[N] estimated_sd_x;
  //vector<lower=0>[N] estimated_sd_y;
  int<lower=1> n_func_types; // number of function types
  int<lower=1> func_type[N]; // function type identifiers
  int<lower=1> guess_num[N]; // timepoint of guess within function
}

parameters {
  real use_true_icpt;
  // Effects of function type and count
  vector[n_func_types] beta_func_type;
  vector[12] beta_guess_num;
  real<lower=0> sd_true; 
  real<lower=0> sd_curr;

  simplex[2] p_rand_strategy;
  real<lower=0, upper=1> max_p;
}


model {
  use_true_icpt ~ normal(0,3);
  beta_guess_num ~ normal(0,3); //what to make these sds?
  beta_func_type ~ normal(0,3);
  
  sd_true ~ exponential(1);
  sd_curr ~ exponential(1);
  max_p ~ beta(1,1);
  p_rand_strategy ~ dirichlet(rep_vector(1,2));
  vector[N] all_log_probs;
  for (i in 1:N) {
    real p_true = max_p * inv_logit(use_true_icpt + beta_func_type[func_type[i]] + beta_guess_num[guess_num[i]]);

    vector[3] log_probs;
    log_probs[1] = log(particle_weight[i]) + log(p_true) + normal_lpdf(x_pred[i] | x_next[i], sd_true) + normal_lpdf(y_pred[i] | y_next[i], sd_true);
    log_probs[2] = log(particle_weight[i]) + log((1-p_true) * p_rand_strategy[1]) + normal_lpdf(x_pred[i] | x_curr[i], sd_curr) + normal_lpdf(y_pred[i] | y_curr[i], sd_curr);
    log_probs[3] = log(particle_weight[i]) + log((1-p_true) * p_rand_strategy[2]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, 1);
    //print(p_rand_strategy);
    //print(log_probs);
    if (is_nan(log_sum_exp(log_probs))) {
        print(p_true);
        print(x_pred[i]);
        print(y_pred[i]);
    }
    all_log_probs += log_sum_exp(log_probs);
    target += log_sum_exp(log_probs);
  }
  print(max(all_log_probs));
  print(target());
}
