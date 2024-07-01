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
  int<lower=1, upper=12> guess_num[N];  // timepoint of guess within function
  vector<lower=0, upper=1>[N] next_is_repeat; // next pt is at a repeat location
  int<lower=1> n_subjs; // number of subjects
  int<lower=1> subj[N]; // subj id
  int<lower=1> n_func_types; // number of function types
  int<lower=1> func_type[N]; // function type identifiers
}

parameters {
  real use_true_icpt;
  vector[n_subjs] use_true_icpt_subj;
  vector[n_func_types] beta_func_type;
  //real<lower=0> beta_guess_num;
  vector[12] beta_guess_num_func_type[n_func_types];
  real<lower=0> sd_true; 
  real<lower=0> sd_curr;
  real<lower=0> sd_lin;
  real<lower=0, upper=1> sd_prop_of_dist;
  real<lower=0, upper=10> sd_subj;
  simplex[3] p_rand_strategy;
  real<lower=0, upper=1> max_p;
}

model { //When beta guess num is a vector, it fails to initialize. divergent transitions...
  use_true_icpt ~ normal(0,3);
  use_true_icpt_subj ~ normal(0, sd_subj);
  //beta_guess_num ~ uniform(0,10);
  for (i in 1:n_func_types) {
    beta_guess_num_func_type[i] ~ normal(0,3); //for each guess_num
  }
  beta_func_type ~ normal(0,3);
  //some noise in distance bt curr and next pt, which is relative to distance
  //between 0 and 1, proportion of distance we are off 
  sd_prop_of_dist ~ beta(1,5);
  sd_true ~ exponential(10);
  sd_curr ~ exponential(10);
  sd_lin ~ exponential(10);
  max_p ~ beta(1,1);
  p_rand_strategy ~ dirichlet(rep_vector(1,3));
  for (i in 1:N) {
    real p_true = max_p * inv_logit(use_true_icpt + use_true_icpt_subj[subj[i]] + beta_func_type[func_type[i]] + beta_guess_num_func_type[func_type[i]][guess_num[i]]);
    vector[4] log_probs;
    //if true
    real sd_dist_x = 0;
    real sd_dist_y = 0;
    if (next_is_repeat[i]==0) {
      sd_dist_x = abs(x_next[i] - x_curr[i]) * sd_prop_of_dist;
      sd_dist_y = abs(y_next[i] - y_curr[i]) * sd_prop_of_dist;
    }
    log_probs[1] = log(p_true) + normal_lpdf(x_pred[i] | x_next[i], sd_true + sd_dist_x) + normal_lpdf(y_pred[i] | y_next[i], sd_true + sd_dist_y);
    //otherwise
    log_probs[2] = log((1-p_true) * p_rand_strategy[1]) + normal_lpdf(x_pred[i] | x_curr[i], sd_curr) + normal_lpdf(y_pred[i] | y_curr[i], sd_curr);
    log_probs[3] = log((1-p_true) * p_rand_strategy[2]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, 1);
    log_probs[4] = log((1-p_true) * p_rand_strategy[3]) + normal_lpdf(x_pred[i] | lin_x_pred[i], sd_lin) + normal_lpdf(y_pred[i] | lin_y_pred[i], sd_lin);
    target += log_sum_exp(log_probs);
  }
}
