# Install packages
pacman::p_load("tidyverse", "DECIPHER", "Biostrings", "skimr", "caret",
               "cowplot", "tidymodels", "ranger", "tree", "rsample", 
                "randomForest","gbm","nnet","e1071","svmpath","lars",
                "glmnet","svmpath")

# Set working directory
setwd("~/Documents/University_of_Minnesota/Wackett_Lab/github/synbio-data-analysis/")

# Read in the raw # Read in the molecular features
molec_fts <- read_csv("data/machine_learning/PC7_molecular_descriptors.csv") %>%
  dplyr::rename(substrate = V1)
molec_fts$substrate <- gsub(" ", "\\.", molec_fts$substrate)
molec_fts$substrate[molec_fts$substrate == "oxidazole"] <- "oxadiazole"

# Read in the sequence features 
seq_fts <- read_csv("data/machine_learning/73_12angstrom_4aa_features.csv") %>%
  dplyr::mutate(raw_org = word(enzyme, sep = "\\.1", 2)) %>%
  dplyr::mutate(org = paste0(word(raw_org, sep = "_", 2), " ", word(raw_org, sep = "_", 3))) %>%
  dplyr::select(-raw_org)
seq_fts$org[seq_fts$enzyme == "4KU5_Xanthomonas_campestris"] <- "Xanthomonas campestris"

# Read in the activity data
activity <- read_csv("data/machine_learning/20191218_all_cmpnds_avg_log_slopes_for_modeling.csv")

# Fix discrepancies in merging names
pseudo1 <- seq_fts$org[grep("Pseudoxanthomonas", seq_fts$org)]
pseudo2 <- activity$org[grep("Pseudoxanthomonas", activity$org)][1]
seq_fts$org[grep("Pseudoxanthomonas", seq_fts$org)] <- pseudo2

leif1 <- seq_fts$org[grep("Leifsonia", seq_fts$org)]
leif2 <- activity$org[grep("Leifsonia", activity$org)][1]
seq_fts$org[grep("Leifsonia", seq_fts$org)] <- leif2

# Now merge everything...
comb <- activity %>%
  dplyr::left_join(., molec_fts, by = "substrate") %>%
  dplyr::left_join(., seq_fts, by = "org")
comb[is.na(comb$PC2),]

# Now remove duplicate rows (hopefully there aren't any)
dedup <- comb[complete.cases(comb),] # no duplicates
dedup <- dedup[!duplicated(comb),]
# write_csv(dedup, "data/machine_learning/20191228_1095_training_examples_12angstrom_features.csv")
rawdat <- dedup 
hist(dedup$activity)

# Only keep variables with nonzero variance
nozdat <- nearZeroVar(rawdat, saveMetrics = TRUE)
which_rem <- rownames(nozdat)[nozdat[,"nzv"] == TRUE]
which_rem

### INCLUDING BOTH SEQUENCE AND CHEMICAL FEATURES
dat <- rawdat %>%
  dplyr::mutate(id = paste0(org, "_", substrate)) %>%
  dplyr::select(-which_rem, -org, -substrate) %>%
  dplyr::select(id, contains("_"),  contains("PC"), activity)
dim(dat) #338 variables remaining with non-zero variance

# Set random seed 
set.seed(20192212)

# Split into test and training data
dat_split <- initial_split(dat, strata = "activity")
dat_train <- training(dat_split)
dat_test  <- testing(dat_split)
nrow(dat_train)/nrow(dat) # 75 %

# Define our response
x_train <- dat_train[,!colnames(dat_train) %in% c("id", "activity")]
x_test <- dat_test[,!colnames(dat_test) %in% c("id", "activity")]
y_train <- dat_train$activity
y_test <- dat_test$activity

# Make a data frame for prediction
df_train <- data.frame(x_train, stringsAsFactors = F, row.names = dat_train$id)

# Complete dataset for training and testing
form_train <- data.frame(cbind(x_train, y_train), stringsAsFactors = F, row.names = dat_train$id)
form_test <- data.frame(cbind(x_test, y_test), stringsAsFactors = F, row.names = dat_test$id)

## First test a generalized linear model! # No penalization
# glm_mod <- train(
#   x = df_train,
#   y = y_train,
#   method = "glm",
#   preProcess = c("center", "scale"),
#   trControl = trainControl(method = "repeatedcv", 
#                            repeats = 3, 
#                            number = 10, 
#                            savePredictions = "final"))
# 
# glm_mod$results # RMSE 0.679 is pretty bad
# 
# important <- names(glm_mod$finalModel$coefficients)[!is.na(glm_mod$finalModel$coefficients)]
# which_coeffs <- important[2:length(important)]
# glm_mod$finalModel$coefficients
# glm_mod$pred
# 
# # Training and test performance
# getTrainPerf(glm_mod)
# glm_pred <- predict(glm_mod, newdata = form_test)

# Now test elastic net (glmnet)
enet_mod <- train(
  x = df_train,
  y = y_train,
  method = "glmnet",
  preProcess = c("center", "scale"),
  trControl = trainControl(method = "repeatedcv", 
                           repeats = 3, 
                           number = 10,
                           savePredictions = "final"))

enet_mod$results # best RMSE is 0.7
important <- names(enet_mod$finalModel$coefficients)[!is.na(enet_mod$finalModel$coefficients)]
important
which_coeffs <- important[2:length(important)]


## Next test MARS
mars_grid <- expand.grid(degree = 1:2, nprune = seq(2, 26, by = 2))

mars_mod <- train(
  x = df_train,
  y = y_train,
  method = "earth",
  tuneGrid = mars_grid,
  preProcess = c("center", "scale"),
  trControl = trainControl(method = "repeatedcv", 
                           repeats = 3, 
                           number = 10,
                           savePredictions = "final"))

# Training and test performance
getTrainPerf(mars_mod)
mars_pred <- predict(mars_mod, newdata = form_test)

# Variable importance
mars_imp <- varImp(mars_mod)
ggplot(mars_imp, top = 20) + xlab("")
mars_mod$results
ggplot(mars_mod$pred, aes(x = obs, y = pred)) +
  geom_abline(col = "green", alpha = .5) + 
  geom_point(alpha = .3) + 
  geom_smooth(se = FALSE, col = "red", 
              lty = 2, lwd = 1, alpha = .5)

obs_pred_plot <- function(x, dat, cutoff = 25, ...) {
  pred_dat <- x %>%
    add_columns(dat, model, year) %>%
    mutate(residuals = obs - pred) 
  ggplot(pred_dat, aes(x = pred, y = obs)) +
    geom_abline(col = "green", alpha = .5) + 
    geom_point(alpha = .3) + 
    geom_smooth(
      se = FALSE, col = "red", 
      lty = 2, lwd = .25, alpha = .5
    ) + 
    geom_text_repel(
      data = dplyr::filter(pred_dat, abs(residuals) > cutoff),
      aes(label = plot_label),
      segment.color = "grey50"
    )
}

# Random forest regression
rf_mod <- train(
  x = df_train,
  y = y_train,
  method = "ranger",
  preProcess = c("center", "scale"),
  trControl = trainControl(method = "repeatedcv", number = 10,
                           repeats = 3,
                           savePredictions = "final"),
  # tuneGrid = tgrid,
  num.trees = 1000,
  # respect.unordered.factors = FALSE,
  verbose = TRUE,
  importance = "permutation") # BEST R MSE is 55.7%

# Confusion matrix
getTrainPerf(rf_mod)
enet_pred <- predict(enet_mod, newdata = form_test)

###Neural networks using nnet
# Currently throws an error
nnet_grid <- expand.grid(.decay = c(0.5, 0.1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7),
                         .size = c(3, 5, 10, 20))

nnet_mod <- train(
  x = df_train,
  y = y_train,
  method = "nnet",
  MaxNWts = 1000000000,
  # size = 1,
  tuneGrid = nnet_grid,
  trControl = trainControl(method = "repeatedcv", repeats = 3,
                           number = 10,
                           verboseIter = T,
                           savePredictions = "final"))

# Confusion matrix
getTrainPerf(nnet_mod)
nnet_pred <- predict(nnet_mod, newdata = form_test)

