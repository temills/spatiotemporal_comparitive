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
  //simplex[M] p_models_group;
  real<lower=0> p_lapse_group_alpha;
  real<lower=0> p_lapse_group_beta;
  real<lower=0, upper=1.0> p_lapse[n_subjs];
  simplex[2] p_lapse_type[n_subjs];
  real<lower=0, upper=1> lapse_sd[n_subjs];
  real<lower=0, upper=1> motor_sd[n_subjs];
}

model {
  vector[M] p_models_group = rep_vector(1.0/M, M); //uniform prior over models
  //p_models_group ~ dirichlet(rep_vector(1,M)); //inferred group prior

  //group level p_lapse
  p_lapse_group_alpha ~ gamma(5, 4);
  p_lapse_group_beta ~ gamma(12, 1);
  p_lapse ~ beta(p_lapse_group_alpha, p_lapse_group_beta);
  p_lapse_type ~ dirichlet(rep_vector(1,2));
  lapse_sd ~ exponential(10);
  motor_sd ~ exponential(10);

  //p_lapse ~ uniform(0, 0.5);

  //compute prob of all datapoints under each model, then marginalize across models
  matrix[n_subjs, M] log_likelihoods = rep_matrix(0, n_subjs, M);
  //compute log lik for each model for each subj, summing across datapoints
  for (i in 1:N) {
    //compute log lik of data for given strategy
    for (m in 1:M) {
      vector[P] particle_log_probs;
      for (p in 1:P) {
        particle_log_probs[p] = log(model_particle_score[i, m, p]) + normal_lpdf(x_pred[i] | model_x_pred[i, m, p], (model_sd_x[i, m, p]^2 + motor_sd[subj[i]]^2)^0.5) + normal_lpdf(y_pred[i] | model_y_pred[i, m, p], (model_sd_y[i, m, p]^2 + motor_sd[subj[i]]^2)^0.5);
      }
      vector[3] data_log_lik;
      //lapse
      data_log_lik[1] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][1]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, upper_bound_y[i]);
      data_log_lik[2] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][2]) + normal_lpdf(x_pred[i] | x_curr[i], lapse_sd[subj[i]]) + normal_lpdf(y_pred[i] | y_curr[i], lapse_sd[subj[i]]);        
      //non-lapse
      data_log_lik[3] = log(1-p_lapse[subj[i]]) + log_sum_exp(particle_log_probs);
      // vector[3] data_log_lik;
      // //lapse
      // data_log_lik[2] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][2]) +  normal_lpdf(x_pred[i] | x_curr[i], lapse_sd[subj[i]]) + normal_lpdf(y_pred[i] | y_curr[i], lapse_sd[subj[i]]);        

      log_likelihoods[subj[i], m] += log_sum_exp(data_log_lik); //multiply lik by lik of data pt, marg over particles
    }
  }
  //now, marginalize across models for each subj
  for (s in 1:n_subjs) {
    vector[M] subj_log_probs;
    //compute unnormalized log probs by weighting likelihoods by model prior
    for (m in 1:M) {
      subj_log_probs[m] = log_likelihoods[s, m] + log(p_models_group[m]);
    }
    target += log_sum_exp(subj_log_probs);
  }
}


generated quantities {
  vector[M] p_models_group = rep_vector(1.0/M, M);
  matrix[n_subjs, M] log_likelihoods = rep_matrix(0, n_subjs, M);
  //compute log lik for each model for each subj, summing across datapoints
  for (i in 1:N) {
    //compute log lik of data for given strategy
    for (m in 1:M) {
      vector[P] particle_log_probs;
      for (p in 1:P) {
        particle_log_probs[p] = log(model_particle_score[i, m, p]) + normal_lpdf(x_pred[i] | model_x_pred[i, m, p], (model_sd_x[i, m, p]^2 + motor_sd[subj[i]]^2)^0.5) + normal_lpdf(y_pred[i] | model_y_pred[i, m, p], (model_sd_y[i, m, p]^2 + motor_sd[subj[i]]^2)^0.5);
      }
      vector[3] data_log_lik;
      //lapse
      data_log_lik[1] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][1]) + uniform_lpdf(x_pred[i] | 0, 1) + uniform_lpdf(y_pred[i] | 0, upper_bound_y[i]);
      data_log_lik[2] = log(p_lapse[subj[i]]) + log(p_lapse_type[subj[i]][2]) + normal_lpdf(x_pred[i] | x_curr[i], lapse_sd[subj[i]]) + normal_lpdf(y_pred[i] | y_curr[i], lapse_sd[subj[i]]);        
      //non-lapse
      data_log_lik[3] = log(1-p_lapse[subj[i]]) + log_sum_exp(particle_log_probs);

      log_likelihoods[subj[i], m] += log_sum_exp(data_log_lik); //multiply lik by prob of data pt, marg over particles
    }
  }
  matrix[n_subjs, M] posterior_probs = rep_matrix(0, n_subjs, M);
  //now compute posterior over models for each subj
  for (s in 1:n_subjs) {
    //first compute unnormalized log probs by weighting likelihoods by model prior
    for (m in 1:M) {
      posterior_probs[s, m] = log_likelihoods[s, m] + log(p_models_group[m]);
    }
    //now normalize and convert to (nonlog) probabilities
    real norm = log_sum_exp(posterior_probs[s, ]);
    for (m in 1:M) {
      posterior_probs[s, m] = exp(posterior_probs[s, m] - norm);
    }
  }
}
