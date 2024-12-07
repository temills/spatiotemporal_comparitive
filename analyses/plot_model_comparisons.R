library(ggplot2)
library(dplyr)
library(tidyr)

paper_theme <- theme_light() + theme( axis.title.x = element_text(size=18),
                                      axis.text.x=element_text(
                                        size = 16), 
                                      axis.title.y = element_text(size = 18, vjust = 1),
                                      axis.text.y  = element_text(size = 16),
                                      strip.text=element_text(size=16),
                                      axis.line.x = element_line(colour = "black"), 
                                      axis.line.y = element_line(colour = "black"),
                                      legend.title=element_text(size=14),
                                      legend.text=element_text(size=12),
                                      panel.grid.major=element_blank(),
                                      panel.grid.minor=element_blank())  

# Read in the results
results <- read.csv("alt_model_results/all_distance_metrics.csv")

# Function to create a boxplot for a specific metric
create_metric_boxplot <- function(data, metric_col, metric_name) {
  ggplot(data, aes(x = model, y = .data[[metric_col]], fill = population)) +
    geom_boxplot(outliers=FALSE) +
    paper_theme +
    labs(
      x = "Model",
      y = metric_name,
      fill = "Population"
    ) +
    scale_fill_brewer(palette = "Set2") 
}

# Create individual plots
emd_plot <- create_metric_boxplot(results, "emd", "Earth Mover's Distance")
js_plot <- create_metric_boxplot(results, "js_div", "Jensen-Shannon Divergence")
hellinger_plot <- create_metric_boxplot(results, "hellinger", "Hellinger Distance")

# Save plots
ggsave("alt_model_results/emd_boxplot.png", emd_plot, width = 10, height = 4.5)
ggsave("alt_model_results/js_boxplot.png", js_plot, width = 10, height = 4.5)
ggsave("alt_model_results/hellinger_boxplot.png", hellinger_plot, width = 10, height = 4.5)


# Function to create a boxplot for a specific metric
create_metric_boxplot_pop <- function(data, metric_col, metric_name) {
  ggplot(data, aes(x = model, y = .data[[metric_col]])) +
    geom_boxplot(outliers=FALSE) +
    paper_theme +
    labs(
      x = "Model",
      y = metric_name,
      fill = "Population"
    ) +
    scale_fill_brewer(palette = "Set2") +
    facet_wrap(~population, nrow=1)

}

# Create individual plots
emd_plot <- create_metric_boxplot_pop(results, "emd", "Earth Mover's Distance")
js_plot <- create_metric_boxplot_pop(results, "js_div", "Jensen-Shannon Divergence")
hellinger_plot <- create_metric_boxplot_pop(results, "hellinger", "Hellinger Distance")

# Save plots
ggsave("alt_model_results/emd_boxplot_pop.png", emd_plot, width = 10, height = 4.5)
ggsave("alt_model_results/js_boxplot_pop.png", js_plot, width = 10, height = 4.5)
ggsave("alt_model_results/hellinger_boxplot_pop.png", hellinger_plot, width = 10, height = 4.5)



results_long <- results %>%
  pivot_longer(
    cols = c(emd, js_div, hellinger),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(
    metric = factor(metric, 
                    levels = c("emd", "js_div", "hellinger"),
                    labels = c("Earth Mover's Distance", 
                               "Jensen-Shannon Divergence", 
                               "Hellinger Distance"))
  )

combined_plot <- ggplot(results_long, aes(x = model, y = value, fill = population)) +
  geom_boxplot(outliers=FALSE) +
  facet_wrap(~metric, scales = "free_y") +
  paper_theme +
  labs(
    x = "Model",
    y = "Value",
    fill = "Population"
  ) +
  scale_fill_brewer(palette = "Set2") +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(size = 12)
  )

ggsave("alt_model_results/combined_metrics_boxplot.png", combined_plot, width = 12, height = 4)
