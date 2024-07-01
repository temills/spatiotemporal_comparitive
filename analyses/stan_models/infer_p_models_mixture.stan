data {
  int<lower=1> N; // number of observations
  int<lower=1> M; // number of models
  int<lower=1> P; // number of model particles

  vector<lower=0, upper=1>[N] x_pred;
  vector<lower=0, upper=1>[N] y_pred;
  vector<lower=0, upper=1>[N] x_curr;
  vector<lower=0, upper=1>[N] y_curr;

  real<lower=0, upper=1> model_x_pred[N, M, P];
  real<lower=0, upper=1> model_y_pred[N, M, P];
  real<lower=0> model_sd_x[N, M, P];
  real<lower=0> model_sd_y[N, M, P];
  real<lower=0, upper=1> model_particle_score[N, M, P];

  real<lower=0, upper=1> upper_bound_y[N];

  int<lower=1> n_subjs; // number of subjects
  int<lower=1> subj[N]; // subj id
}

parameters {
  simplex[M] p_models_group;
  real<lower=0> conc_param;
  simplex[M] p_models_ind[n_subjs];
  
  real<lower=0> motor_sd[n_subjs];
  real<lower=0> p_lapse_group_alpha;
  real<lower=0> p_lapse_group_beta;
  real<lower=0, upper=1.0> p_lapse[n_subjs];
  simplex[2] p_lapse_type[n_subjs];
  real<lower=0, upper=1> lapse_sd[n_subjs];

  //real<lower=0, upper=0.5> p_lapse[n_subjs];
  //real<lower=0, upper=1> lapse_sd[n_subjs];
}

model {
  p_models_group ~ dirichlet(rep_vector(1,M));
  conc_param ~ gamma(1, 0.2);
  p_models_ind ~ dirichlet(p_models_group * conc_param);
  motor_sd ~ exponential(10);
  p_lapse_group_alpha ~ gamma(5, 4);
  p_lapse_group_beta ~ gamma(12, 1);
  p_lapse ~ beta(p_lapse_group_alpha, p_lapse_group_beta);
  p_lapse_type ~ dirichlet(rep_vector(1,2));
  lapse_sd ~ exponential(10);

  //motor_sd ~ uniform(0,1.0);
  //p_lapse ~ uniform(0, 0.5);
  //lapse_sd ~ uniform(0,1.0);

  for (i in 1:N) {
    vector[3] log_probs;
    //if lapse
    //either random guess
    log_probs[1] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][1]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, upper_bound_y[i]);
    //or around prev pt
    log_probs[2] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][2]) +  normal_lpdf(x_pred[i] | x_curr[i], lapse_sd[subj[i]]) + normal_lpdf(y_pred[i] | y_curr[i], lapse_sd[subj[i]]);

    //if not lapse
    //p under each model
    vector[M] model_log_probs;
    for (m in 1:M) {
        vector[P] particle_log_probs;
        for (p in 1:P) {
            particle_log_probs[p] = log(model_particle_score[i, m, p]) + normal_lpdf(x_pred[i] | model_x_pred[i, m, p], (model_sd_x[i, m, p]^2 + motor_sd[subj[i]]^2)^0.5) + normal_lpdf(y_pred[i] | model_y_pred[i, m, p], (model_sd_y[i, m, p]^2 + motor_sd[subj[i]]^2)^0.5);
        }
        model_log_probs[m] = log(1-p_lapse[subj[i]]) + log(p_models_ind[subj[i]][m]) + log_sum_exp(particle_log_probs);
    }
    log_probs[3] = log_sum_exp(model_log_probs);

    target += log_sum_exp(log_probs);
  }
}
