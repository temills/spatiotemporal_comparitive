library(ggplot2)
library(reshape)
library(grid)
library(dplyr)
library(gridExtra)
library(lme4)
library(reghelper)
library(RColorBrewer)
library(robustbase)
library(tidylog)
library(hash)
library(rstan)
library(png)
library(gtable)
library(transport)
library(proxy)
library(ks)  # for kernel density estimation
library(philentropy)  # for Jensen-Shannon divergence
setwd("~/Documents/other_projects/spatiotemporal_python/shared/github_models/spatiotemporal_comparitive/analyses/")


paper_theme <- theme_light() + theme( axis.title.x = element_text(size=18),
                                      axis.text.x=element_text(colour="#292929", 
                                                               size = 14), 
                                      axis.title.y = element_text(size = 18, vjust = 1),
                                      axis.text.y  = element_text(size = 14, colour="#292929"),
                                      strip.text=element_text(size=16,color="black"),
                                      strip.background = element_rect(colour = "grey50", fill = "white"),
                                      panel.background = element_rect(fill = "white", colour = "grey50"),
                                      axis.ticks.x=element_blank(),axis.ticks.y=element_blank(),
                                      axis.line.x = element_line(colour = "black"), 
                                      axis.line.y = element_line(colour = "black"),
                                      legend.title=element_text(size=18),
                                      legend.text=element_text(size=15),
                                      panel.grid.major = element_blank(), panel.grid.minor = element_blank())


preprocess_df_model <- function(df) {
  logsumexp <- function(x) {
    max_x <- max(x)
    max_x + log(sum(exp(x - max_x)))
  }
  if ("sample" %in% colnames(df)) {
    df <- df %>% filter(sample%%100000==0) %>%
      mutate(particle_sample = paste(particle, sample, sep = "_")) %>%
      mutate(particle_sample_id = as.integer(factor(particle_sample))) %>%
      rename(og_particle=particle) %>%
      rename(particle=particle_sample_id)
  }
  df<-df[order(df$tpt),]
  df <- df %>%
    group_by(tpt, seq_id) %>%
    mutate(total_log_likelihood = logsumexp(score)) %>%
    ungroup() %>%
    mutate(posterior = exp(score - total_log_likelihood)) %>%
    group_by(seq_id, particle) %>%
    arrange(tpt) %>%  # Sort the DataFrame by tpt to ensure correct lagging
    mutate(prev_x = lag(true_x), prev_y = lag(true_y)) %>%
    ungroup() %>%
    mutate(true_dist=((true_x-prev_x)**2. + (true_y-prev_y)**2.)**0.5) %>%
    mutate(err_x=pred_x-true_x) %>%
    mutate(err_y=pred_y-true_y) %>%
    mutate(abs_err = ((err_x**2)+(err_y)**2) **0.5) %>%  
    mutate(abs_rel_err = abs_err/(true_dist)) %>%
    #group_by(seq_id, tpt) %>%
    #mutate(norm_abs_rel_err = sum(abs_rel_err * posterior, na.rm=T)) %>%
    #ungroup() %>%
    rename(x_curr = prev_x, y_curr = prev_y, x_next = true_x, y_next = true_y, x_pred = pred_x, y_pred = pred_y, func.type = seq_id)
  return(df)
}

preprocess_df_human <- function(df) {
  df <- df[order(df$tpt),] %>%
    rename(x_curr = prev_x, y_curr = prev_y, x_next = true_x, y_next = true_y, x_pred = response_x, y_pred = response_y, func.type = seq_id) %>%
    group_by(subject_id, trial_idx, tpt) %>%
    mutate(true_dist=((x_next-x_curr)**2. + (y_next-y_curr)**2.)**0.5) %>%
    mutate(x_err=x_pred-x_next) %>%
    mutate(y_err=y_pred-y_next) %>%
    mutate(abs_err = ((x_err**2)+(y_err)**2) **0.5) %>%  
    mutate(abs_rel_err = abs_err/(true_dist)) %>%
    mutate(dist_from_prev = (((x_pred-x_curr)**2)+((y_pred-y_curr)**2)) **0.5) %>%
    ungroup() %>%
    filter(func.type != "example_line")
  return(df)
}

preprocess_df_monkey <- function(df) {
  df <- df[order(df$n),] %>%
    rename(tpt = n, subject_id = monkey_name) %>%
    group_by(subject_id, game_n, tpt) %>%
    mutate(true_dist=((x_next-x_curr)**2. + (y_next-y_curr)**2.)**0.5) %>%
    mutate(x_err=x_pred-x_next) %>%
    mutate(y_err=y_pred-y_next) %>%
    mutate(abs_err = ((x_err**2)+(y_err)**2) **0.5) %>%  
    mutate(abs_rel_err = abs_err/(true_dist)) %>%
    mutate(dist_from_prev = (((x_pred-x_curr)**2)+((y_pred-y_curr)**2)) **0.5) %>%
    ungroup() %>%
    mutate(run_id = group_indices(., subject_id, func.type, game_n))
  return(df)
}

add_perfect_subject <- function(df) {
  #add a subject who's predictions are the same as x_next, y_next at each tpt
  perfect_subject <- df %>%
    group_by(func.type, tpt) %>%
    summarize(x_curr = mean(x_curr), y_curr = mean(y_curr), x_next = mean(x_next), y_next = mean(y_next)) %>%
    ungroup() %>%
    mutate(x_pred = x_next, y_pred = y_next, subject_id = "perfect")
  # Combine the original dataframe and the "perfect" subject dataframe
  df <- bind_rows(df, perfect_subject)
}



df_kid <- preprocess_df_human(read.csv("data/participants/kids.csv")) %>% select(-X.1)
df_adult <- preprocess_df_human(read.csv("data/participants/adults.csv"))
df_monkey <- preprocess_df_monkey(read.csv("data/participants/monkeys_all.csv"))

df_gpnc <- preprocess_df_model(read.csv('data/models/gpnc.csv'))
df_gpsl <- preprocess_df_model(read.csv('data/models/gpsl.csv'))
df_ridge <- preprocess_df_model(read.csv('data/models/ridge.csv'))
df_lot <- preprocess_df_model(read.csv('data/models/lot.csv'))
df_lin <- preprocess_df_model(read.csv('data/models/linear.csv'))



prepare_distribution <- function(df, is_model = FALSE) {
  if (is_model) {
    dist_data <- df %>%
      select(x_pred, y_pred, posterior) %>%
      mutate(weight = posterior / sum(posterior))
  } else {
    dist_data <- df %>%
      select(x_pred, y_pred) %>%
      group_by(x_pred, y_pred) %>%
      summarise(count = n(), .groups = 'drop') %>%
      mutate(weight = count / sum(count))
  }
  
  return(list(
    locations = as.matrix(dist_data[, c("x_pred", "y_pred")]),
    weights = dist_data$weight
  ))
}


calculate_emd_condition <- function(model_df, population_df, func_type, timepoint) {
  print(paste(paste("running", func_type), timepoint))
  model_data <- model_df %>%
    filter(func.type == func_type, tpt == timepoint)
  
  pop_data <- population_df %>%
    filter(func.type == func_type, tpt == timepoint)
    if (nrow(model_data) == 0 || nrow(pop_data) == 0) {
    return(NA)
  }
  
  
  model_dist <- prepare_distribution(model_data, is_model = TRUE)
  pop_dist <- prepare_distribution(pop_data, is_model = FALSE)
  
  costm <- proxy::dist(model_dist$locations, pop_dist$locations, method = "Euclidean")
  
  emd <- wasserstein(
    a = model_dist$weights,
    b = pop_dist$weights,
    costm = as.matrix(costm)
  )
  
  return(emd)
}

calculate_kde_distances <- function(model_df, population_df, func_type_val, timepoint_val, grid_size = 50) {
    #this was done by claude so need to check if it's correct
  print(paste(paste("running KDE for", func_type_val), timepoint_val))
  model_data <- model_df %>%
    filter(func.type == func_type_val, tpt == timepoint_val)
  
  pop_data <- population_df %>%
    filter(func.type == func_type_val, tpt == timepoint_val)
  
  if (nrow(model_data) == 0 || nrow(pop_data) == 0) {
    return(list(js_div = NA, hellinger = NA))
  }
    model_dist <- prepare_distribution(model_data, is_model = TRUE)
  pop_dist <- prepare_distribution(pop_data, is_model = FALSE)
  
  if (any(!is.finite(model_dist$weights)) || any(!is.finite(pop_dist$weights))) {
    print("Warning: Non-finite weights detected")
    return(list(js_div = NA, hellinger = NA))
  }
  
  if (any(!is.finite(model_dist$locations)) || any(!is.finite(pop_dist$locations))) {
    print("Warning: Non-finite locations detected")
    return(list(js_div = NA, hellinger = NA))
  }
  
  model_dist$weights <- model_dist$weights / sum(model_dist$weights)
  pop_dist$weights <- pop_dist$weights / sum(pop_dist$weights)
  
  jitter_amt <- 1e-10
  model_points <- model_dist$locations + matrix(rnorm(nrow(model_dist$locations) * 2, 0, jitter_amt), 
                                              ncol = 2)
  pop_points <- pop_dist$locations + matrix(rnorm(nrow(pop_dist$locations) * 2, 0, jitter_amt), 
                                          ncol = 2)
  
  x_range <- range(c(model_points[,1], pop_points[,1]))
  y_range <- range(c(model_points[,2], pop_points[,2]))
  
  if (any(!is.finite(x_range)) || any(!is.finite(y_range))) {
    print("Warning: Non-finite ranges detected")
    print(paste("X range:", paste(x_range, collapse = ", ")))
    print(paste("Y range:", paste(y_range, collapse = ", ")))
    return(list(js_div = NA, hellinger = NA))
  }
  
  pad <- pmax(0.1 * abs(c(diff(x_range), diff(y_range))), 1e-5)
  x_range <- x_range + c(-pad[1], pad[1])
  y_range <- y_range + c(-pad[2], pad[2])
  
  x_grid <- seq(x_range[1], x_range[2], length.out = grid_size)
  y_grid <- seq(y_range[1], y_range[2], length.out = grid_size)
  eval_points <- expand.grid(x = x_grid, y = y_grid)
  
  h_scale <- 0.1
  tryCatch({
    model_kde <- kde(x = model_points, 
                    w = model_dist$weights,
                    H = diag(2) * h_scale)
    
    pop_kde <- kde(x = pop_points, 
                   w = pop_dist$weights,
                   H = diag(2) * h_scale)
    
    # Evaluate KDEs on grid
    model_density <- predict(model_kde, x = as.matrix(eval_points))
    pop_density <- predict(pop_kde, x = as.matrix(eval_points))
    
    # Check for valid densities
    if (any(!is.finite(model_density)) || any(!is.finite(pop_density))) {
      print("Warning: Non-finite densities detected")
      return(list(js_div = NA, hellinger = NA))
    }
    
    # Normalize densities
    model_density <- model_density / sum(model_density)
    pop_density <- pop_density / sum(pop_density)
    
    # Calculate Jensen-Shannon divergence
    js_div <- JSD(rbind(model_density, pop_density))
    
    # Calculate Hellinger distance
    hellinger <- sqrt(0.5 * sum((sqrt(model_density) - sqrt(pop_density))^2))
    
    return(list(js_div = js_div, hellinger = hellinger))
  }, error = function(e) {
    print(paste("KDE error:", e$message))
    return(list(js_div = NA, hellinger = NA))
  })
}

compare_model_population <- function(model_df, population_df) {
  conditions <- population_df %>%
    filter(tpt > 2) %>%
    select(func.type, tpt) %>%
    distinct()
  
  results <- conditions %>%
    rowwise() %>%
    mutate(
      kde_metrics = list(calculate_kde_distances(model_df, population_df, func.type, tpt)),
      emd = calculate_emd_condition(model_df, population_df, func.type, tpt)
    ) %>%
    mutate(
      js_div = kde_metrics$js_div,
      hellinger = kde_metrics$hellinger
    ) %>%
    select(-kde_metrics)
  
  return(results)
}

run_all_comparisons <- function() {
  models <- list(
    gpnc = df_gpnc,
    gpsl = df_gpsl,
    ridge = df_ridge,
    lot = df_lot,
    linear = df_lin
  )
  
  populations <- list(
    adult = df_adult,
    child = df_kid,
    monkey = df_monkey
  )
  
  all_results <- list()
  
  for (model_name in names(models)) {
    for (pop_name in names(populations)) {
      print(paste("Comparing", model_name, "with", pop_name))
      
      comparison_results <- compare_model_population(
        models[[model_name]], 
        populations[[pop_name]]
      ) %>%
        mutate(
          model = model_name,
          population = pop_name
        )
      
      all_results[[paste(model_name, pop_name, sep="_")]] <- comparison_results
    }
  }
  
  combined_results <- bind_rows(all_results)
  return(combined_results)
}

all_comparisons <- run_all_comparisons()

write.csv(all_comparisons, "alt_model_results/all_distance_metrics.csv", row.names = FALSE)

summary_stats <- all_comparisons %>%
  group_by(model, population) %>%
  summarise(
    mean_emd = mean(emd, na.rm = TRUE),
    mean_js = mean(js_div, na.rm = TRUE),
    mean_hellinger = mean(hellinger, na.rm = TRUE),
    sd_emd = sd(emd, na.rm = TRUE),
    sd_js = sd(js_div, na.rm = TRUE),
    sd_hellinger = sd(hellinger, na.rm = TRUE),
    n_comparisons = sum(!is.na(emd))
  )
