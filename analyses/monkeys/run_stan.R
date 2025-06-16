
library(ggplot2)
#library(reshape)
#library(grid)
library(dplyr)
# library(gridExtra)
# library(lme4)
# library(reghelper)
# library(RColorBrewer)
# library(robustbase)
# library(tidylog)
library(hash)
library(rstan)

#library(rjson)

# library(rstudioapi)
# current_path = rstudioapi::getActiveDocumentContext()$path
# setwd(dirname(current_path ))
# getwd()
# options(
#   stanc.allow_optimizations = TRUE,
#   stanc.auto_format = TRUE
# )

paper_theme <- theme_light() + theme( axis.title.x = element_text(size=22),
                                      axis.text.x=element_text(
                                        size = 18), 
                                      axis.title.y = element_text(size = 22, vjust = 1),
                                      axis.text.y  = element_text(size = 18),
                                      strip.text=element_text(size=16),
                                      axis.line.x = element_line(colour = "black"), 
                                      axis.line.y = element_line(colour = "black"),
                                      legend.title=element_text(size=20),
                                      legend.text=element_text(size=16),
                                      panel.grid.major=element_blank(),
                                      #   panel.background = element_rect(color = NA), 
                                      panel.grid.minor=element_blank())  
out_folder <- "figs/"


f_weighted_sd <- function(means, sds, weights)  {
  var_wtd = sum(weights * sds**2) + sum(weights * means**2) - (sum(weights*means)**2)
  return (var_wtd**0.5)
  
}

inv_logit <- function(x) { exp(x)/(1+exp(x))}

logit <- function(p) {log(p) - log(1-p)}


add_rank_time_column <- function(dataframe) {
  # Convert 'time' column to a date format, ignoring the clock time information
  dataframe$date <- as.Date(dataframe$Current_time, format = "%a %b %d %H:%M:%S %Y")
  
  # Create a dataframe with unique dates and their corresponding rank order
  unique_dates <- dataframe %>%
    distinct(date) %>%
    arrange(date) %>%
    mutate(rank_time = row_number())
  
  h <- hash()
  for (i in 1:nrow(unique_dates)) {
    date <- unique_dates$date[i]
    rank_time <- unique_dates$rank_time[i]
    h[date] = rank_time
  }
  
  # Join the unique_dates dataframe with the original dataframe to add the 'rank_time' column
  # dataframe <- left_join(dataframe, unique_dates, by = "date")
  dataframe <- dataframe %>%
    rowwise() %>%
    mutate(ranked_day = h[[as.character(date)]])
  
  return(dataframe)
}

# Function to extract and add subject-level parameter means to df.blocked_10
add_subject_level_params <- function(fit, df, posterior_samples_lst,
                                     subject_id_var, param_prefix) {
  # Extract posterior samples
  
  # Get the list of parameter names that start with the specified prefix
  param_names <- grep(paste0("^", param_prefix), names(posterior_samples_lst), value = TRUE)
  
  if (length(param_names) > 0) {
    for (param_name in param_names) {
      # Initialize a vector to store means
      subject_means <- rep(NA, nrow(df))
      
      for (s in 1:df$NSUBJ) {
        # Find the rows in df.blocked_10 that correspond to subject s
        subject_rows <- df[[subject_id_var]] == s
        
        # Calculate the mean for this subject from posterior samples
        subject_means[subject_rows] <- mean(posterior_samples_lst[[param_name]][, s])
      }
      
      # Add means to df.blocked_10 as a new column
      df[paste0("mean_", param_name)] <- subject_means
    }
  } else {
    cat("No matching parameters found with prefix '", param_prefix, "'.\n")
  }
  
  return(df)
}




df <- read.csv("all_monkey_data/train.csv")
screen_w <- df$screen_w[1]
screen_h <- df$screen_h[1]

n_games <- max(df$game_n)

df$id <- seq.int(1,nrow(df))
df$func.name <- df$func_id
df$attempt_number <- ifelse(is.na(df$attempt_number), 0, df$attempt_number)

df <- add_rank_time_column(df)

ranked_days <- df %>%
  group_by(monkey_name) %>%
  distinct(ranked_day) %>%
  arrange(ranked_day) %>%
  mutate(rank_day = row_number()) %>%
  ungroup()



unique_sequences_df <- df %>%
  group_by(func.name, n) %>%
  top_n(n = 1, wt = id) %>%
  select(func.name, n, x_curr, y_curr) %>%
  group_by(func.name) %>%
  arrange(n) %>%
  mutate(
    # Calculate deltas for x
    delta_x = x_curr - lag(x_curr),
    delta_x_2 = lag(x_curr) - lag(x_curr, 2),
    
    # Calculate deltas for y
    delta_y = y_curr - lag(y_curr),
    delta_y_2 = lag(y_curr) - lag(y_curr, 2),
    
    # Handle NA values for deltas
    delta_x = ifelse(is.na(delta_x), 0, delta_x),
    delta_y = ifelse(is.na(delta_y), 0, delta_y),
    delta_x_2 = ifelse(is.na(delta_x_2), delta_x, delta_x_2),
    delta_y_2 = ifelse(is.na(delta_y_2), delta_y, delta_y_2),
    x_lin = x_curr + delta_x,
    y_lin = y_curr + delta_y

  ) %>%
  select(func.name, n, x_lin, y_lin) %>%  # Only keep necessary columns
  ungroup()
# 
# # Step 2: Merge x_lin and y_lin back into df
df <- df %>%
  left_join(unique_sequences_df, by = c("func.name", "n"))



df <- df %>%
  left_join(ranked_days, by = c("monkey_name", "ranked_day")) %>%
  rowwise() %>%
  mutate(func.type = gsub("\\.\\d+$", "", func.name)) %>%
  mutate(t_id = paste(r_id, func.name, game_n)) %>%
  group_by(monkey_name) %>%
  mutate(rank_day = rank_day - min(rank_day)+1) %>%
  mutate(game_n_total = game_n + (rank_day-1)*n_games) %>%
  filter((guess_number <= 10) | is.na(guess_number)) %>%
  group_by(func.type) %>%
  mutate(min_rank_day = min(rank_day)) %>%
  ungroup() %>%
  arrange(min_rank_day) %>%
  mutate(func.type = factor(func.type, levels = unique(func.type))) %>%
  arrange(monkey_name, rank_day, game_n, n, attempt_number) %>%
  group_by(monkey_name, r_id,  game_n, attempt_number) %>%
  mutate(guess_dist_from_curr=((x_pred-x_curr)**2. + (y_pred-y_curr)**2.)**0.5) %>%
  
  
  group_by(monkey_name, func.name, r_id, game_n) %>%
  
  mutate(new_day=(game_n==0)*game_n_total) %>%
  mutate(true_dist=((x_next-x_curr)**2. + (y_next-y_curr)**2.)**0.5) %>%
  mutate(x_err=x_pred-x_next) %>%
  mutate(y_err=y_pred-y_next) %>%
  mutate(abs_err = ((x_err**2)+(y_err)*2.)**0.5) %>%  
  mutate(abs_rel_err = abs_err/(true_dist)) %>%
  ungroup() %>%
  
  arrange(rank_day, game_n, n) %>%
  group_by(monkey_name, func.type) %>%
  mutate(func_examples = cumsum(!duplicated(t_id))) %>%
  ungroup() %>%
  filter(attempt_number == 1) %>%
  #mutate(func_examples_std = func_examples/max(func_examples)) #%>%
  mutate(func_examples_std = (func_examples - mean(func_examples))/sd(func_examples)) 

Sys.setenv(STAN_NUM_THREADS=4)


stan_df <- df %>%
  filter(!is.na(x_pred) & (!is.na(y_pred))) %>%
  mutate(x_curr = x_curr/screen_w, x_pred = x_pred/screen_w, x_next = x_next/screen_w,
         y_curr = y_curr/screen_h, y_pred =y_pred/screen_h, y_next = y_next/screen_h,
         x_lin = x_lin/screen_w, y_lin = y_lin/screen_h) %>%
  mutate(x_lin = x_lin * (x_lin > 0) * (x_lin <= 1) + 1* (x_lin > 1)) %>%
  mutate(y_lin = y_lin * (y_lin > 0) * (y_lin <= 1) + 1* (y_lin > 1)) %>%
  mutate(screen_ratio=screen_h/screen_w) %>%
  filter(monkey_name == "BP24") 


stan_df$func_type_numeric <- as.numeric(as.factor(stan_df$func.type))

stan_data <- list(
  N = length(stan_df$x_pred),
  screen_ratio = stan_df$screen_ratio[1],
  x_pred = stan_df$x_pred,
  y_pred = stan_df$y_pred,
  x_next = stan_df$x_next,
  y_next = stan_df$y_next,
  x_curr = stan_df$x_curr,
  y_curr = stan_df$y_curr,
  x_lin = stan_df$x_lin,
  y_lin = stan_df$y_lin,
  n_func_types = length(unique(stan_df$func.type)),
  func_type = stan_df$func_type_numeric,
  n_seen = stan_df$func_examples_std)


fit <- stan(file="independent_stan_model.stan", data=stan_data, iter=200, chains=4, cores=4, warmup=100)

saveRDS(fit, "model_fits/bp24_ind.rds")

