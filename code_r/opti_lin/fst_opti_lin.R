#' ---
#' title: "CES log lin formulas working with micro estimates, corrected, linear spline"
#' output:
#'   html_document:
#'     df_print: paged
#'     number_sections: true
#'     toc: true
#'     toc_depth: 3
#'   html_notebook:
#'     number_sections: true
#'   word_document:
#'     number_sections: true
#'   pdf_document:
#'     number_sections: true
#'     toc: true
#'     toc_depth: 3
#' urlcolor: blue
#' ---
#' 
#' Back to **[Fan](https://fanwangecon.github.io/)**'s REconTools Homepage **[Table of Content](https://fanwangecon.github.io/REconTools/)**
#' 
#' # Outline
#' 
#' There is a dataset with child attributes, nutritional inputs and outputs. Run regression to estimate some input output relationship first. Then generate required inputs for code.
#' 
#' 1. Required Input
#'   + @param df tibble data table including variables using svr names below each row is potentially an individual who will receive alternative allocations
#'   + @param svr_A_i string name of the A_i variable, dot product of covariates and coefficients
#'   + @param svr_alpha_i string name of the alpha_i variable, individual specific elasticity information
#'   + @param svr_beta_i string name of the beta_i variable, relative preference weight for each child
#'   + @param svr_N_i string name of the vector of existing inputs, based on which to compute aggregate resource
#'   + @param fl_N_hat float total resource avaible for allocation, if not specific, sum by svr_N_i
#'   + @param fl_rho float preference for equality for the planner
#'   + @return a dataframe that expands the df inputs with additional results.
#' 2. The structure assumes some regression has already taken place to generate the i specific variables listed. and
#' 
#' Doing this allows for lagged intereaction that are time specific in an arbitrary way.
#' 
#' ## Set Up
#' 
## ----GlobalOptions, echo = T, results = 'hide', message=F, warning=F----------
rm(list = ls(all.names = TRUE))
options(knitr.duplicate.label = 'allow')

## ----loadlib, echo = T, results = 'hide', message=F, warning=F----------------
library(tidyverse)
library(tidymodels)
library(REconTools)
library(knitr)
library(kableExtra)
# file name
st_file_name = 'fst_opti_lin'
# Generate R File
purl(paste0(st_file_name, ".Rmd"), output=paste0(st_file_name, ".R"), documentation = 2)
# Generate PDF and HTML
# rmarkdown::render("C:/Users/fan/REconTools/support/function/fs_funceval.Rmd", "pdf_document")
# rmarkdown::render("C:/Users/fan/REconTools/support/function/fs_funceval.Rmd", "html_document")

#' 
#' ## Get Data
#' 
## ----Load Packages and Process Data-------------------------------------------
# Load Library

# Select Cebu Only
df_hw_cebu_m24 <- df_hgt_wgt %>% filter(S.country == 'Cebu' & svymthRound == 24 & prot > 0 & hgt > 0) %>% drop_na()

# Generate Discrete Version of momEdu
df_hw_cebu_m24 <- df_hw_cebu_m24 %>%
    mutate(momEduRound = cut(momEdu,
                             breaks=c(-Inf, 10, Inf),
                             labels=c("MEduLow","MEduHigh"))) %>%
    mutate(hgt0med = cut(hgt0,
                             breaks=c(-Inf, 50, Inf),
                             labels=c("h0low","h0high")))

df_hw_cebu_m24$momEduRound = as.factor(df_hw_cebu_m24$momEduRound)
df_hw_cebu_m24$hgt0med = as.factor(df_hw_cebu_m24$hgt0med)

# Attach
attach(df_hw_cebu_m24)

#' 
#' # Regression with Data and Construct Input Arrays
#' 
#' ## Linear Regression
#' 
## ----Linear Regression--------------------------------------------------------
# Input Matrix
mt_lincv <- model.matrix(~ hgt0 + wgt0)
mt_linht <- model.matrix(~ sex:hgt0med - 1)

# Regress Height At Month 24 on Nutritional Inputs with controls
rs_hgt_prot_lin = lm(hgt ~ prot:mt_linht + mt_lincv - 1)
print(summary(rs_hgt_prot_lin))
rs_hgt_prot_lin_tidy = tidy(rs_hgt_prot_lin)

#' 
#' ## Log-Linear Regression
#' 
## ----Log-Linear Regression----------------------------------------------------
# Input Matrix
mt_logcv <- model.matrix(~ hgt0 + wgt0)
mt_loght <- model.matrix(~ sex:hgt0med - 1)

# Log and log regression for month 24
rs_hgt_prot_log = lm(log(hgt) ~ log(prot):mt_loght + mt_logcv - 1)
print(summary(rs_hgt_prot_log))
rs_hgt_prot_log_tidy = tidy(rs_hgt_prot_log)

#' 
#' ## Construct Input Arrays $A_i$ and $\alpha_i$
#' 
## ----Post Regression Input Processing-----------------------------------------

# Generate A_i
ar_Ai_lin <- mt_lincv %*% as.matrix(rs_hgt_prot_lin_tidy %>% filter(!str_detect(term, 'prot')) %>% select(estimate))
ar_Ai_log <- mt_logcv %*% as.matrix(rs_hgt_prot_log_tidy %>% filter(!str_detect(term, 'prot')) %>% select(estimate))

# Generate alpha_i
ar_alphai_lin <- mt_linht %*% as.matrix(rs_hgt_prot_lin_tidy %>% filter(str_detect(term, 'prot')) %>% select(estimate))
ar_alphai_log <- mt_loght %*% as.matrix(rs_hgt_prot_log_tidy %>% filter(str_detect(term, 'prot')) %>% select(estimate))

# Child Weight
ar_beta <- rep(1/length(ar_Ai_lin), times=length(ar_Ai_lin))

# Initate Dataframe that will store all estimates and optimal allocation relevant information
mt_opti <- cbind(ar_alphai_lin, ar_Ai_lin, ar_beta)
ar_st_varnames <- c('alpha', 'A', 'beta')
tb_opti <- as_tibble(mt_opti) %>% rename_all(~c(ar_st_varnames))

# Unique beta, A, and alpha groups
tb_opti_unique <- tb_opti %>% group_by(!!!syms(ar_st_varnames)) %>%
                    arrange(!!!syms(ar_st_varnames)) %>%
                    summarise(n_obs_group=n())

#' 
#' # Optimal Allocations
#' 
#' ## Common Parameters for Optimal Allocation
#' 
## ----Set Allocation Parameters------------------------------------------------
# Child Count
df_hw_cebu_m24_full <- df_hw_cebu_m24
it_obs = dim(df_hw_cebu_m24)[1]

# Total Resource Count
ar_prot_data = df_hw_cebu_m24$prot
fl_N_agg = sum(ar_prot_data)

# Vector of Planner Preference
ar_rho = c(seq(-200, -100, length.out=5), seq(-100, -25, length.out=5), seq(-25, -5, length.out=5), seq(-5, -1, length.out=5), seq(-1, -0.01, length.out=5), seq(0.01, 0.25, length.out=5), seq(0.25, 0.99, length.out=5))
ar_rho = c(-50)
ar_rho = unique(ar_rho)

#' 
#' ## Optimal Linear Allocation (CRS)
#' 
#' This also works with any CRS CES.
#' 
#' ### Optimal Linear Allocation Hard-Coded
#' 
## ----Optimal Linear Allocation Hard Code All Rho------------------------------
# Optimal Linear Equation
# Planner Inputs
mt_hev_lin = matrix(, nrow = length(ar_rho), ncol = 2)
mt_opti_N = matrix(, nrow = it_obs, ncol = length(ar_rho))

# A. First Loop over Planner Preference
# Generate Rank Order
for (it_rho_ctr in seq(1,length(ar_rho))) {
  rho = ar_rho[it_rho_ctr]

  # B. Generate V4, Rank Index Value, rho specific
  # tb_opti <- tb_opti %>% mutate(!!paste0('rv_', it_rho_ctr) := A/((alpha*beta))^(1/(1-rho)))
  tb_opti <- tb_opti %>% mutate(rank_val = A/((alpha*beta))^(1/(1-rho)))

  # c. Generate Rank Index
  tb_opti <- tb_opti %>% arrange(rank_val) %>% mutate(rank_idx = row_number())

  # d. Populate lowest index alpha, beta, and A to all rows
  tb_opti <- tb_opti %>% mutate(lowest_rank_A = A[rank_idx==1]) %>%
                mutate(lowest_rank_alpha = alpha[rank_idx==1]) %>%
                mutate(lowest_rank_beta = beta[rank_idx==1])

  # e. relative slope and relative intercept with respect to lowest index
  tb_opti <- tb_opti %>%
                mutate(rela_slope_to_lowest =
                         (((lowest_rank_alpha*lowest_rank_beta)/(alpha*beta))^(1/(rho-1))*(lowest_rank_alpha/alpha))
                      ) %>%
                mutate(rela_intercept_to_lowest =
                         ((((lowest_rank_alpha*lowest_rank_beta)/(alpha*beta))^(1/(rho-1))*(lowest_rank_A/alpha)) - (A/alpha))
                      )

  # f. cumulative sums
  tb_opti <- tb_opti %>%
                mutate(rela_slope_to_lowest_cumsum =
                         cumsum(rela_slope_to_lowest)
                      ) %>%
                mutate(rela_intercept_to_lowest_cumsum =
                         cumsum(rela_intercept_to_lowest)
                      )

  # g. inverting cumulative slopes and intercepts
  tb_opti <- tb_opti %>%
                mutate(rela_slope_to_lowest_cumsum_invert =
                         (1/rela_slope_to_lowest_cumsum)
                      ) %>%
                mutate(rela_intercept_to_lowest_cumsum_invert =
                         ((-1)*(rela_intercept_to_lowest_cumsum)/(rela_slope_to_lowest_cumsum))
                      )

  # h. Relative x-intercept points
  tb_opti <- tb_opti %>%
                mutate(rela_x_intercept =
                         (-1)*(rela_intercept_to_lowest/rela_slope_to_lowest)
                      )

  # i. Inverted relative x-intercepts
  tb_opti <- tb_opti %>%
                mutate(opti_lowest_spline_knots =
                         (rela_intercept_to_lowest_cumsum + rela_slope_to_lowest_cumsum*rela_x_intercept)
                      )

  # j. Sort by order of receiving transfers/subsidies
  tb_opti <- tb_opti %>% arrange(rela_x_intercept)

  # k. Find position of subsidy
  tb_opti <- tb_opti %>% arrange(opti_lowest_spline_knots) %>%
                mutate(tot_devi = opti_lowest_spline_knots - fl_N_agg) %>%
                arrange((-1)*case_when(tot_devi < 0 ~ tot_devi)) %>%
                mutate(allocate_lowest =
                         case_when(row_number() == 1 ~
                                     rela_intercept_to_lowest_cumsum_invert +
                                     rela_slope_to_lowest_cumsum_invert*fl_N_agg)) %>%
                mutate(allocate_lowest = allocate_lowest[row_number() == 1]) %>%
                mutate(opti_allocate =
                         rela_intercept_to_lowest +
                         rela_slope_to_lowest*allocate_lowest) %>%
                mutate(opti_allocate =
                         case_when(opti_allocate >= 0 ~ opti_allocate)) %>%
                mutate(opti_allocate_total = sum(opti_allocate, na.rm=TRUE))

}

# lineplot <- tb_opti %>%
#     gather(variable, value, -month) %>%
#     ggplot(aes(x=month, y=value, colour=variable, linetype=variable)) +
#         geom_line() +
#         geom_point() +
#         labs(title = 'Mean and SD of Temperature Acorss US Cities',
#              x = 'Months',
#              y = 'Temperature in Fahrenheit',
#              caption = 'Temperature data 2017') +
#         scale_x_continuous(labels = as.character(df_temp_mth_summ$month),
#                            breaks = df_temp_mth_summ$month)


#' 
#' ### Optimal Linear Allocation Hard-Coded
#' 
## ----Optimal Linear Allocation Hard Code All Rho Old--------------------------
# Optimal Linear Equation
# Planner Inputs
mt_hev_lin = matrix(, nrow = length(ar_rho), ncol = 2)
mt_opti_N = matrix(, nrow = it_obs, ncol = length(ar_rho))

# Generate
for (it_rho_ctr in seq(1,length(ar_rho))) {
  rho = ar_rho[it_rho_ctr]

  ar_term_b = ar_Ai_lin*(ar_alphai_lin*(1/(rho - 1)))
  ar_term_c = ar_Ai_lin*(ar_alphai_lin*(1/(rho - 1)))
  ar_term_d = (ar_alphai_lin*(rho/(rho - 1)))

  # Child Specific Optimal Allocation Array to Store
  ar_opti_lin = matrix(, nrow = it_obs, ncol = 1)
  for (m in seq(1:it_obs)) {
    fl_topright_q = sum((ar_term_b[m] - ar_term_c)/ar_term_d)
    fl_bottom_q = sum((ar_alphai_lin[m]/ar_alphai_lin)^(rho/(rho-1)))
    fl_opti_q = (fl_N_agg - fl_topright_q)/fl_bottom_q
    ar_opti_lin[m] = fl_opti_q
  }

  # Min and Max
  ar_opti_lin = pmin(fl_N_agg, pmax(0, ar_opti_lin))
  mt_opti_N[,it_rho_ctr] = ar_opti_lin
  df_hw_cebu_m24_full = cbind(df_hw_cebu_m24_full, ar_opti_lin)

  # Utilities
  fl_v_data_lin = sum((ar_Ai_lin + ar_prot_data*ar_alphai_lin - 70)^rho)^(1/rho)
  fl_v_opti_lin = sum((ar_Ai_lin + ar_opti_lin*ar_alphai_lin - 70)^rho)^(1/rho)

  ## HEV
  fl_hev = (fl_v_opti_lin/fl_v_data_lin - 1)
  mt_hev_lin[it_rho_ctr,1] = rho;
  mt_hev_lin[it_rho_ctr,2] = fl_hev;
}

#' 
#' ### Optimal Linear Allocation Pseudo-Function
#' 
## ----Optimal Linear Allocation Equation Line by Line Test one Rho Selected Individuals----
# Randomly test 10 individuals/rho combinations to see if the same results produced by the functional (vectorized) code below as the looped code above.

set.seed(123)
for (it_ctr in seq(1, 10)) {
  # Which Individual to Test
  it_indi_ctr_test = sample(it_obs, 1)
  it_rho_ctr_test = sample(length(ar_rho), 1)

  # Get Inputs for Function
  fl_A = ar_Ai_lin[it_indi_ctr_test]
  fl_alpha = ar_alphai_lin[it_indi_ctr_test]
  fl_N = df_hw_cebu_m24$prot[it_indi_ctr_test]
  ar_A = ar_Ai_lin
  ar_alpha = ar_alphai_lin
  fl_rho = ar_rho[it_rho_ctr_test]
  # Existing optimal choice
  fl_opti_loop = mt_opti_N[it_indi_ctr_test, it_rho_ctr_test]

  # From Paper Proposition 1
  # top of fraction
  fl_p1_s1 = (fl_A * ((fl_alpha) * (1 / (fl_rho - 1))))
  ar_p1_s2 = (ar_A * ((ar_alpha) * (1 / (fl_rho - 1))))
  ar_p1_s3 = ((ar_alpha) * (fl_rho / (fl_rho - 1)))
  fl_p1_s3 = fl_N_agg - sum((fl_p1_s1 - ar_p1_s2) / ar_p1_s3)

  # bottom of fraction
  ar_p2 = (fl_alpha / ar_alpha) ^ (fl_rho / (fl_rho - 1))

  # overall
  fl_opti_equa = fl_p1_s3 / sum(ar_p2)
  fl_opti_equa = pmin(fl_N_agg, pmax(0, fl_opti_equa))

  print(
    paste0(
      'it_ctr:',
      it_ctr,
      ', fl_rho:',
      fl_rho,
      ', i:',
      it_indi_ctr_test,
      ', fl_opti_equa:',
      fl_opti_equa,
      ', fl_opti_loop:',
      fl_opti_loop
    )
  )
}

#' 
#' ### Optimal Linear Allocation Function DPLYR
#' 
## ----Optimal Linear Allocation Functional Equation DPLYR one rho all individuals----

# Define Explicit Optimal Choice Function
ffi_linear_dplyrdo <- function(fl_A, fl_alpha, fl_rho, ar_A, ar_alpha, fl_N_agg){

  # Apply Function From Paper Proposition 1
  fl_p1_s1 = (fl_A * ((fl_alpha) * (1 / (fl_rho - 1))))
  ar_p1_s2 = (ar_A * ((ar_alpha) * (1 / (fl_rho - 1))))
  ar_p1_s3 = ((ar_alpha) * (fl_rho / (fl_rho - 1)))
  fl_p1_s3 = fl_N_agg - sum((fl_p1_s1 - ar_p1_s2) / ar_p1_s3)

  # bottom of fraction
  ar_p2 = (fl_alpha / ar_alpha) ^ (fl_rho / (fl_rho - 1))

  # overall
  fl_opti_equa = fl_p1_s3 / sum(ar_p2)
  fl_opti_equa = pmin(fl_N_agg, pmax(0, fl_opti_equa))


  return(fl_opti_equa)
}

# Child Heterogeneity as Matrix
mt_nN_by_nQ_A_alpha = cbind(ar_Ai_lin, ar_alphai_lin, ar_prot_data)
ar_st_col_names = c('fl_A', 'fl_alpha', 'ar_prot_data')
tb_nN_by_nQ_A_alpha <- as_tibble(mt_nN_by_nQ_A_alpha) %>% rename_all(~c(ar_st_col_names))

# fl_A, fl_alpha are from columns of tb_nN_by_nQ_A_alpha
fl_rho = ar_rho[5]
tb_nN_by_nQ_A_alpha = tb_nN_by_nQ_A_alpha %>% rowwise() %>%
                        mutate(dplyr_eval_opti = ffi_linear_dplyrdo(fl_A, fl_alpha, fl_rho,
                                                                    ar_Ai_lin, ar_alphai_lin,
                                                                    fl_N_agg))
# Show
kable(tb_nN_by_nQ_A_alpha[1:10,]) %>%
  kable_styling(bootstrap_options = c("striped", "hover", "responsive"))


#' 
#' ### Optimal Linear Allocation Function DPLYR All Rho
#' 
## ----Optimal Linear Allocation Functional Equation DPLYR all rho all individuals----

# Generate Data, all individuals specific parameters
mt_nN_by_nQ_A_alpha = cbind(ar_Ai_lin, ar_alphai_lin, ar_prot_data)
ar_st_col_names = c('fl_A', 'fl_alpha', 'ar_prot_data')
tb_nN_by_nQ_A_alpha <- as_tibble(mt_nN_by_nQ_A_alpha) %>% rename_all(~c(ar_st_col_names))
# Duplicate to rhos
tb_nN_by_nQ_A_alpha_mesh_rho <- tb_nN_by_nQ_A_alpha %>% expand_grid(fl_rho = ar_rho) %>%
                                  arrange(fl_A, fl_alpha, fl_rho) %>%
                                  select(fl_rho, !!!syms(ar_st_col_names))

# fl_A, fl_alpha are from columns of tb_nN_by_nQ_A_alpha
tb_nN_by_nQ_A_alpha_mesh_rho = tb_nN_by_nQ_A_alpha_mesh_rho %>% rowwise() %>%
                              mutate(dplyr_eval_opti = ffi_linear_dplyrdo(fl_A, fl_alpha, fl_rho,
                                                                    ar_Ai_lin, ar_alphai_lin,
                                                                    fl_N_agg)) %>%
                              ungroup()

# Check if Total Allocations sum Up to Same Level for Each RHO
tb_nN_by_nQ_A_alpha_mesh_rho %>%
  group_by(fl_rho) %>%
  summarise(N_opti_all_sum = sum(dplyr_eval_opti))%>%
  kable() %>%
  kable_styling(bootstrap_options = c("striped", "hover", "responsive"))

# Show
kable(tb_nN_by_nQ_A_alpha_mesh_rho[1:50,]) %>%
  kable_styling(bootstrap_options = c("striped", "hover", "responsive"))

#' 
#' 
#' ### Graphical Illustration of Optimal Allocation
#' 
## -----------------------------------------------------------------------------
tb_hev_lin <- as_tibble(mt_hev_lin) %>% mutate(id = row_number())

lineplot_lin <- tb_hev_lin %>%
    ggplot(aes(x=id, y=V2)) +
        geom_line() +
        geom_point() +
        labs(title = 'HEV and Preference',
             x = 'pref',
             y = 'HEV',
             caption = 'Linear') +
        scale_x_continuous(labels = as.character(tb_hev_lin$V1),
                           breaks = tb_hev_lin$V1)
print(lineplot_lin)


#' 
#' ## Optimal LogLinear Allocation
#' 
#' This also works with any CRS CES.
#' 
#' ### Optimal LogLinear Allocation Hard-Coded
#' 
## ----Optimal Loglinear Allocation---------------------------------------------

mt_hev_log = matrix(, nrow = length(ar_rho), ncol = 2)

for (it_rho_ctr in seq(1,length(ar_rho))) {
  rho = ar_rho[it_rho_ctr]
  fl_N_hat = sum(df_hw_cebu_m24$prot)

  ar_term_b = ar_Ai_lin*(ar_alphai_lin*(1/(rho - 1)))
  ar_term_c = ar_Ai_lin*(ar_alphai_lin*(1/(rho - 1)))
  ar_term_d = (ar_alphai_lin*(rho/(rho - 1)))

  # Child Specific Optimal Allocation Array to Store
  ar_opti_lin = matrix(, nrow = it_obs, ncol = 1)
  for (m in seq(1:it_obs)) {
    fl_topright_q = sum((ar_term_b[m] - ar_term_c)/ar_term_d)
    fl_bottom_q = sum((ar_alphai_lin[m]/ar_alphai_lin)^(rho/(rho-1)))
    fl_opti_q = (fl_N_hat - fl_topright_q)/fl_bottom_q
    ar_opti_lin[m] = fl_opti_q
  }

  # Min and Max
  ar_opti_lin = pmin(fl_N_hat, pmax(0, ar_opti_lin))
  df_hw_cebu_m24_full = cbind(df_hw_cebu_m24_full, ar_opti_lin)

  # Utilities
  fl_v_data_lin = sum((ar_Ai_lin + prot*ar_alphai_lin - 70)^rho)^(1/rho)
  fl_v_opti_lin = sum((ar_Ai_lin + ar_opti_lin*ar_alphai_lin - 70)^rho)^(1/rho)

  ## HEV
  fl_hev = (fl_v_opti_lin/fl_v_data_lin - 1)
  mt_hev_log[it_rho_ctr,1] = rho;
  mt_hev_log[it_rho_ctr,2] = fl_hev;
}

tb_hev_log <- as_tibble(mt_hev_log) %>% mutate(id = row_number())

lineplot_log <- tb_hev_log %>%
    ggplot(aes(x=id, y=V2)) +
        geom_line() +
        geom_point() +
        labs(title = 'HEV and Preference',
             x = 'pref',
             y = 'HEV',
             caption = 'Linear') +
        scale_x_continuous(labels = as.character(tb_hev_log$V1),
                           breaks = tb_hev_log$V1)
print(lineplot_log)


