data {
  int<lower=1> N; // number of observations
  vector<lower=0, upper=1>[N] x_pred;
  vector<lower=0, upper=1>[N] y_pred;
  vector<lower=0, upper=1>[N] x_next;
  vector<lower=0, upper=1>[N] y_next;
  vector<lower=0, upper=1>[N] x_curr;
  vector<lower=0, upper=1>[N] y_curr;
  vector<lower=0, upper=1>[N] lin_x_pred;
  vector<lower=0, upper=1>[N] lin_y_pred;
  real<lower=0, upper=1> upper_bound_y[N];
  real<lower=0, upper=1> upper_bound_x[N];
  int<lower=1, upper=12> guess_num[N];  // timepoint of guess within function
  real guess_num_std[N];  // timepoint of guess within function
  int<lower=1> n_subjs; // number of subjects
  int<lower=1> subj[N]; // subj id
  int<lower=1> n_func_types; // number of function types
  int<lower=1> func_type[N]; // function type identifiers
}

parameters {
  real use_true_icpt;
  vector[n_func_types] beta_func_type;
  //real<lower=0> beta_guess_num;
  real<lower=0> beta_guess_num_func_type[n_func_types];
  real<lower=0> motor_sd; 
  real<lower=0> prev_sd; 
  simplex[2] p_rand_strategy;
  //real<lower=0, upper=1> max_p;
} 

model { //When beta guess num is a vector, it fails to initialize. divergent transitions...

  use_true_icpt ~ normal(0,3);
  beta_guess_num_func_type ~ normal(0,3); //for each guess_num
  beta_func_type ~ normal(0,3);
  motor_sd ~ exponential(1);
  prev_sd ~ exponential(1);
  p_rand_strategy ~ dirichlet(rep_vector(1,2)); //prev, rand, lin

  for (i in 1:N) {
    real p_true = inv_logit(use_true_icpt + beta_func_type[func_type[i]] + beta_guess_num_func_type[func_type[i]]*guess_num_std[i]);
    vector[3] log_probs;
    log_probs[1] = log(p_true) + normal_lpdf(x_pred[i] | x_next[i], motor_sd) + normal_lpdf(y_pred[i] | y_next[i], motor_sd);
    //otherwise 
    log_probs[2] = log((1-p_true) * p_rand_strategy[1]) + normal_lpdf(x_pred[i] | x_curr[i], prev_sd) + normal_lpdf(y_pred[i] | y_curr[i], prev_sd);
    log_probs[3] = log((1-p_true) * p_rand_strategy[2]) + uniform_lpdf(x_pred[i] | 0, upper_bound_x[i]) + uniform_lpdf(y_pred[i] | 0, upper_bound_y[i]);
    //log_probs[4] = log((1-p_true) * p_rand_strategy[3]) + normal_lpdf(x_pred[i] | lin_x_pred[i], motor_sd) + normal_lpdf(y_pred[i] | lin_y_pred[i], motor_sd);
    target += log_sum_exp(log_probs);
  }
}
