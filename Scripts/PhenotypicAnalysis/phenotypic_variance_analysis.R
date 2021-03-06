## PopVarValidation
## Analysis of observed genetic variance
##
## 
## Author: Jeff Neyhart
## Last modified: August 29, 2018
## 

# Load the source script
repo_dir <- getwd()
source(file.path(repo_dir, "source.R"))

# Load the pbr library
library(pbr)
library(broom)
library(ggridges)
library(cowplot)
library(modelr)


# Load the PVV BLUEs
load(file.path(data_dir, "PVV_BLUE.RData"))
# Load the S2 BLUEs and filter
load("path/to/S2_tidy_BLUE.RData")

vp_family_tomodel <- s2_tidy_BLUE %>%
  filter(trait %in% traits, line_name %in% c(pot_pars, exper), str_detect(trial, "PVV"))


boot_rep <- 1000
alpha <- 0.05
i <- 0.1


### Calculate genetic variance within families
### 

## First if the same line is measured in two different trials, calculate an environment mean
vp_family_tomodel1 <- vp_family_tomodel %>%
  filter(line_name %in% exper) %>%
  group_by(trait, environment) %>%
  do({
    df <- .
    
    if (n_distinct(df$trial) > 1) {
      
      fit <- lm(value ~ -1 + line_name + trial, data = df)
      fit_tidy <- tidy(fit) %>% filter(str_detect(term, "line_name")) %>% 
        mutate(line_name = str_replace(term, "line_name", "")) %>% 
        select(line_name, value = estimate, std.error)
      
      df %>% 
        mutate(trial = NA) %>% 
        distinct(trial, environment, location, year, trait) %>% 
        cbind(., fit_tidy)
      
    } else {
      
      df
    }
    
  }) %>% ungroup()


## Calculate variance by fitting a model with G and GE

## Use the stage-one BLUEs to calculate variance
vp_family_tomodel1 <- vp_family_tomodel1 %>% 
  mutate(family = str_extract(line_name, "4[0-9]{3}"))


# Fit a model per family per trait
vp_family_varG1 <- vp_family_tomodel1 %>% 
  group_by(trait, family) %>%
  do(calc_varG(data = ., method = "lmer")) %>%
  ungroup()




# Plot mean versus varG
vp_family_varG_method1 <- vp_family_varG1 %>% 
  ungroup() %>%
  mutate(heritability = map_dbl(h2, "heritability"),
         varG = map(h2, "var_comp")) %>% 
  unnest(varG) %>% 
  filter(source == "line_name") %>% 
  select(-source)

vp_family_varG_method1 %>% 
  qplot(x = family_mean, y = variance, data = .) + 
  facet_wrap(~ trait, ncol = 2, scales = "free")


## Calculate the superior progeny mean
vp_family_musp <- vp_family_tomodel1 %>% 
  group_by(trait, family) %>%
  do(calc_mean(data = .)) %>%
  ungroup()


### Confidence intervals
# Use parametric bootstrapping to estimate confidence intervals for mu and varG

vp_family_varG_boot <- vp_family_varG1 %>%
  group_by(trait, family) %>%
  do({
    out <- .
    fit <- out$fit[[1]]
    
    # Define a function for harvesting the statistics
    stat <- function(x) c(mu = unname(fixef(x)[1]), varG = subset(as.data.frame(VarCorr(x)), grp == "line_name", vcov, drop = T))
    boot_out <- bootMer(x = fit, FUN = stat, nsim = boot_rep)
    
    # Return results
    data_frame(
      parameter = c("mu", "varG"),
      base = boot_out$t0,
      bias = colMeans(boot_out$t) - boot_out$t0,
      se = apply(X = boot_out$t, MARGIN = 2, FUN = sd),
      lower = apply(X = boot_out$t, MARGIN = 2, FUN = quantile, probs = alpha / 2),
      upper = apply(X = boot_out$t, MARGIN = 2, FUN = quantile, probs = 1 - (alpha / 2)) )
    
  })



# Use non-parametric bootsrapping for the superior progeny mean
vp_family_musp_boot <- vp_family_musp %>% 
  group_by(trait, family) %>%
  do({
    out <- .
    boot_samples <- unnest(out, means) %>% 
      filter(term != "family_mean") %>% 
      select(mean) %>%
      bootstrap(n = boot_rep)
    
    boot_out <- boot_samples$strap %>%
      map_dbl(~as.data.frame(.) %>% 
            subset(mean <= quantile(mean, probs = i), mean, drop = T) %>% 
            mean() )
    
    # Return results
    data_frame(
      parameter = "musp",
      base = out$mu_sp,
      bias = mean(boot_out) - out$mu_sp,
      se = sd(boot_out),
      lower = quantile(boot_out, probs = alpha / 2),
      upper = quantile(boot_out, probs = 1 - (alpha / 2)) )
    
  })


# Combine
vp_family_boot <- bind_rows(vp_family_varG_boot, vp_family_musp_boot) %>%
  arrange(trait, family) %>%
  ungroup()

## Plot with CI
g_family_boot <- vp_family_boot %>%  
  mutate(facet = str_c(trait, "_", parameter),
         expectation = base + bias) %>%
  ggplot(aes(x = family, y = base, ymin = lower, ymax = upper)) + 
  geom_errorbar(position = position_dodge(0.9), width = 0.5) + 
  geom_point(aes(color = parameter, shape = "base")) + 
  # geom_point(aes(y = expectation, color = parameter, shape = "expectation")) +
  facet_wrap(~ facet, scale = "free", nrow = 3, 
             labeller = labeller(facet = function(x) str_split(x, pattern = "_", simplify = T)[,1])) + 
  theme_acs() +
  theme(axis.text.x = element_blank(), axis.title = element_blank())
    
# Save this
ggsave(filename = "family_parameter_boot.jpg", plot = g_family_boot, path = fig_dir, height = 6, width = 6, dpi = 1000)
    





## Calculate mean and genetic variance for FHB Severity separately for
## STP and CRM
vp_family_varG1_FHB <- vp_family_tomodel1 %>% 
  filter(trait == "FHBSeverity") %>%
  group_by(location, family) %>%
  do(calc_varG(data = ., method = "lmer")) %>%
  ungroup()

## Calculate the superior progeny mean
vp_family_FHB_musp <- vp_family_tomodel1 %>% 
  filter(trait == "FHBSeverity") %>%
  group_by(location, family) %>%
  do(calc_mean(data = .)) %>%
  ungroup()


# Plot mean versus varG
vp_family_varG_FHB_method1 <- vp_family_varG1_FHB %>% 
  ungroup() %>%
  mutate(heritability = map_dbl(h2, "heritability"),
         varG = map(h2, "var_comp")) %>% 
  unnest(varG) %>% 
  filter(source == "line_name") %>% 
  select(-source)


vp_family_varG_FHB_method1 %>% 
  qplot(x = family_mean, y = variance, data = .) + 
  facet_wrap(~ location, ncol = 2, scales = "free")


### Confidence intervals
# Use parametric bootstrapping to estimate confidence intervals for mu and varG

vp_family_varG_FHB_boot <- vp_family_varG1_FHB %>%
  group_by(location, family) %>%
  do({
    out <- .
    fit <- out$fit[[1]]
    
    # Define a function for harvesting the statistics
    stat <- function(x) c(mu = unname(fixef(x)[1]), varG = subset(as.data.frame(VarCorr(x)), grp == "line_name", vcov, drop = T))
    boot_out <- bootMer(x = fit, FUN = stat, nsim = boot_rep)
    
    # Return results
    data_frame(
      parameter = c("mu", "varG"),
      base = boot_out$t0,
      bias = colMeans(boot_out$t) - boot_out$t0,
      se = apply(X = boot_out$t, MARGIN = 2, FUN = sd),
      lower = apply(X = boot_out$t, MARGIN = 2, FUN = quantile, probs = alpha / 2),
      upper = apply(X = boot_out$t, MARGIN = 2, FUN = quantile, probs = 1 - (alpha / 2)) )
    
  })



# Use non-parametric bootsrapping for the superior progeny mean
vp_family_musp_FHB_boot <- vp_family_FHB_musp %>% 
  group_by(location, family) %>%
  do({
    out <- .
    boot_samples <- unnest(out, means) %>% 
      filter(term != "family_mean") %>% 
      select(mean) %>%
      bootstrap(n = boot_rep)
    
    boot_out <- boot_samples$strap %>%
      map_dbl(~as.data.frame(.) %>% 
                subset(mean <= quantile(mean, probs = i), mean, drop = T) %>% 
                mean() )
    
    # Return results
    data_frame(
      parameter = "musp",
      base = out$mu_sp,
      bias = mean(boot_out) - out$mu_sp,
      se = sd(boot_out),
      lower = quantile(boot_out, probs = alpha / 2),
      upper = quantile(boot_out, probs = 1 - (alpha / 2)) )
    
  })


# Combine
vp_family_boot_FHB <- bind_rows(vp_family_varG_FHB_boot, vp_family_musp_FHB_boot) %>%
  arrange(location, family) %>%
  ungroup()

## Plot with CI
g_family_boot <- vp_family_boot_FHB %>%  
  mutate(facet = str_c(location, "_", parameter),
         expectation = base + bias) %>%
  ggplot(aes(x = family, y = base, ymin = lower, ymax = upper)) + 
  geom_errorbar(position = position_dodge(0.9), width = 0.5) + 
  geom_point(aes(color = parameter, shape = "base")) + 
  # geom_point(aes(y = expectation, color = parameter, shape = "expectation")) +
  facet_wrap(~ facet, scale = "free", nrow = 2, 
             labeller = labeller(facet = function(x) str_split(x, pattern = "_", simplify = T)[,1])) + 
  theme_acs() +
  theme(axis.text.x = element_blank(), axis.title = element_blank())

# Save this
ggsave(filename = "family_parameter_boot_FHB.jpg", plot = g_family_boot, path = fig_dir, height = 6, width = 6, dpi = 1000)



## Calculate the correlation among families between HD and FHB in Crookston and St. Paul
vp_family_tomodel2 <- vp_family_tomodel1 %>% 
  filter(trait %in% c("FHBSeverity", "HeadingDate"))

# Fit a model for each location
vp_family_FHB_HD_mean <- vp_family_tomodel2 %>%
  group_by(location, trait) %>%
  do(calc_mean(data = .)) %>%
  ungroup()

# Calculate the correlation
vp_family_FHB_HD_mean1 <- vp_family_FHB_HD_mean %>% 
  ungroup() %>% 
  unnest(means) %>% 
  filter(term != "family_mean") %>% 
  select(location, line_name = term, trait, mean) %>% 
  spread(trait, mean) %>% 
  filter_at(vars(FHBSeverity, HeadingDate), all_vars(!is.na(.)))


vp_family_FHB_HD_mean1 %>% 
  group_by(location) %>%
  do(neyhart::bootstrap(x = .$FHBSeverity, y = .$HeadingDate, "cor"))

# location statistic    base     se      bias ci_lower ci_upper
# 1 CRM      cor       -0.512  0.0189 0.0000804  -0.548   -0.473 
# 2 STP      cor        0.0163 0.0248 0.0000572  -0.0327   0.0672

vp_family_FHB_HD_mean1 %>% 
  qplot(x = FHBSeverity, y = HeadingDate, data = ., facets = ~ location) + 
  theme_acs()





## Save the variance calculations
save("vp_family_varG_method1", "vp_family_varG_FHB_method1", "vp_family_musp", "vp_family_FHB_musp", 
     "vp_family_boot", "vp_family_boot_FHB", file = file.path(result_dir, "vp_family_analysis.RData"))


load(file.path(result_dir, "vp_family_analysis.RData"))









## Summarize the number of environments per family
family_env <- vp_family_tomodel %>% 
  filter(line_name %in% exper) %>% 
  mutate(family = str_extract(line_name, "4[0-9]{3}")) %>% 
  group_by(trait, family) %>% 
  summarize(nEnv = n_distinct(environment)) %>% 
  ungroup()



# Create a summary table with the family, number of inidividuals, number of evalulation environments,
# mean, range, and the estimated heritability
family_summ <- left_join(vp_pedigree, vp_family_varG_method1) %>% 
  left_join(., family_env) %>%
  select(-family_mean, -variance) %>% 
  mutate(heritability = formatC(heritability, digits = 2, format = "g")) %>%
  group_by(family) %>%
  mutate(nEnv = max(nEnv)) %>%
  spread(trait, heritability) %>%
  arrange(desc(Nind))

# Save this
write_csv(x = family_summ, path = file.path(fig_dir, "family_summary.csv"))

## Plot size versus heritability
g_size_h <- left_join(vp_pedigree, vp_family_varG_method1) %>% 
  select(-family_mean, -variance) %>%
  ggplot(aes(x = Nind, y = heritability)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  facet_grid(~ trait) +
  theme_acs()



## Create a df of the mean and range of the mean, varG, mu_sp, and h2
family_estimate_summ <- vp_family_varG_method1 %>% 
  left_join(., select(vp_family_musp, trait, family, mu_sp)) %>%
  gather(variable, value, -trait, -family) %>% 
  mutate(variable = str_replace_all(variable, param_replace),
         variable = factor(variable, levels = c("mu", "V[G]", "mu[sp]", "heritability"))) %>%
  group_by(trait, variable) %>%
  summarize_at(vars(value), funs(min, max, mean)) %>%
  mutate_at(vars(min, max, mean), ~formatC(x = ., digits = 2, format = "g") %>% str_trim()) %>%
  mutate(annotation = str_c(mean, " (", min, ", ", max, ")")) %>%
  select(-min:-mean) %>% 
  spread(variable, annotation)

## Save
# Save this
write_csv(x = family_estimate_summ, path = file.path(fig_dir, "family_estimate_summary.csv"))





# What is the mean, min, and max of heritability estimates?
vp_family_varG_method1 %>% 
  group_by(trait) %>% 
  summarize_at(vars(heritability), funs(min, max, mean))

# trait            min   max  mean
# 1 FHBSeverity 1.47e-15 0.280 0.102
# 2 HeadingDate 1.16e- 1 0.841 0.488
# 3 PlantHeight 0.       0.761 0.412



## How many of the families per trait had variance significantly greater than zero?
vp_family_boot %>% 
  filter(parameter == "varG") %>%
  rowwise() %>% 
  mutate(annotation = ifelse(!between(0, lower, upper), "*", "")) %>%
  group_by(trait) %>%
  summarize(n_fam = n(),
            n_sig = sum(annotation == "*"),
            p_sig = n_sig / n())

# trait       n_sig p_sig
# 1 FHBSeverity     7 0.467
# 2 HeadingDate    23 0.852
# 3 PlantHeight    23 0.852






## Using the pedigree information and the BLUEs, correlate the MPV with the family mean

# Add the BLUEs for each parent and calculate MPV
family_MPV <- vp_pedigree %>%
  rename_all(str_to_lower) %>%
  left_join(., vp_BLUE, by = c("par1" = "line_name")) %>% 
  left_join(., vp_BLUE, by = c("par2" = "line_name", "trait")) %>% 
  select(family, par1, par2, trait, par1_value = value.x, par2_value = value.y) %>% 
  arrange(trait, family) %>%
  mutate(mpv = (par1_value + par2_value) / 2,
         family = str_c("4", family))

family_MPV_mean <- family_MPV %>% 
  left_join(., vp_family_varG_method1)

# Plot
g_mean_mpv <- family_MPV_mean %>% 
  # filter(!(trait == "FHBSeverity" & family_mean > 22.5)) %>% # Remove outlier 
  qplot(x = mpv, y = family_mean, data = .) + 
  facet_wrap(~ trait, ncol = 2, scales = "free")

ggsave(filename = "family_mean_mpv.jpg", plot = g_mean_mpv, path = fig_dir, height = 5, width = 5, dpi = 1000)


# Correlate
family_MPV_mean %>%
  group_by(trait) %>%
  # filter(!(trait == "FHBSeverity" & family_mean > 22.5)) %>% # Remove outlier
  do(neyhart::bootstrap(x = .$mpv, y = .$family_mean, fun = "cor", boot.reps = boot_rep))

# trait       statistic  base     se     bias ci_lower ci_upper
# 1 FHBSeverity cor       0.243 0.258   0.00871   -0.279    0.713
# 2 HeadingDate cor       0.723 0.0773  0.00885    0.572    0.867
# 3 PlantHeight cor       0.613 0.0963 -0.0103     0.397    0.762



## What is the relationship between family mean and superior progeny mean?
vp_family_estimates <- vp_family_musp %>% 
  select(-means) %>% 
  left_join(., select(vp_family_varG_method1, -family_mean))

# Mean and range of means and variances
vp_family_estimates %>% 
  gather(parameter, estimate, family_mean, mu_sp, variance) %>% 
  group_by(trait, parameter) %>% 
  summarize_at(vars(estimate), funs(min, max, mean))

# trait       parameter        min   max  mean
# 1 FHBSeverity family_mean  2.14e+ 1 30.8   25.1  
# 4 FHBSeverity variance     4.87e-14 15.4    4.95 
# 5 HeadingDate family_mean  4.79e+ 1 55.8   52.5  
# 8 HeadingDate variance     4.33e- 1  8.57   2.27 
# 9 PlantHeight family_mean  7.30e+ 1 90.8   81.8  
# 12 PlantHeight variance     0.       18.4    6.37

## Ratio of mean to variance
vp_family_estimates %>% 
  group_by(trait) %>% 
  summarize_at(vars(family_mean, mu_sp, variance), funs(var)) %>% 
  mutate(t = variance / family_mean)

## t is the ratio of variance of variance to variance of mean

# trait       family_mean mu_sp variance     t
# 1 FHBSeverity        8.37  6.48    30.9  3.69 
# 2 HeadingDate        5.99  7.32     3.27 0.545
# 3 PlantHeight       24.8  22.7     23.7  0.954



vp_family_estimates %>% 
  group_by(trait) %>% 
  do(neyhart::bootstrap(x = .$family_mean, y = .$mu_sp, fun = "cor", boot.reps = boot_rep))
# 
# trait       statistic  base     se     bias ci_lower ci_upper
# 1 FHBSeverity cor       0.755 0.137   0.00802    0.463    0.954
# 2 HeadingDate cor       0.963 0.0133 -0.00141    0.928    0.980
# 3 PlantHeight cor       0.956 0.0163 -0.00112    0.916    0.979

# Plot
g_vp_means <- vp_family_estimates %>% 
  ggplot(aes(x = family_mean, y = mu_sp)) +
  geom_point() +
  facet_wrap(~trait, ncol = 2, scales = "free") +
  theme_acs()

ggsave(filename = "vp_mean_corr.jpg", plot = g_vp_means, path = fig_dir, height = 4, width = 8, dpi = 1000)

# Relationship between variance and mu_sp
vp_family_estimates %>% 
  group_by(trait) %>% 
  summarize(cor = cor(variance, mu_sp))

# trait          cor
# 1 FHBSeverity -0.629
# 2 HeadingDate -0.599
# 3 PlantHeight -0.190

## A negative relationship is expected, since a larger variance should lead to lower mu_sp

# Plot
g_vp_musp_var <- vp_family_estimates %>% 
  ggplot(aes(x = variance, y = mu_sp)) +
  geom_point() +
  facet_wrap(~trait, nrow = 1, scales = "free")

ggsave(filename = "vp_musp_var_corr.jpg", plot = g_vp_means, path = fig_dir, height = 4, width = 8, dpi = 1000)


