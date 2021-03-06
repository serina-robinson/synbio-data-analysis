# Read in the raw data
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

# Only keep variables with nonzero variance
nozdat <- nearZeroVar(dedup, saveMetrics = TRUE)
which_rem <- rownames(nozdat)[nozdat[,"nzv"] == TRUE]
which_rem




# write_csv(dedup, "data/machine_learning/20191228_1095_training_examples_12angstrom_features.csv")
dat <- dedup %>%
  dplyr::mutate(id = paste0(org, "_", substrate)) %>%
  dplyr::mutate(is_active = as.factor(case_when(activity == 0 ~ "N",
                                                TRUE ~ "Y"))) %>%
  dplyr::select(-which_rem, -org, -substrate) %>%
  dplyr::select(id, contains("_"),  contains("PC"), is_active)

# Set random seed 
set.seed(1234)

# Split into test and training data
table(dat$is_active)
dat_split <- initial_split(dat, strata = "is_active")
dat_train <- training(dat_split)
dat_test  <- testing(dat_split)
nrow(dat_train)/nrow(dat) # 75 %

# Define our response
x_train <- dat_train[,!colnames(dat_train) %in% c("id", "is_active")]
x_test <- dat_test[,!colnames(dat_test) %in% c("id", "is_active")]
y_train <- dat_train$is_active
y_test <- dat_test$is_active
table(dat$is_active)

# Make a data frame for prediction
df_train <- data.frame(x_train, stringsAsFactors = F, row.names = dat_train$id)

# Complete dataset for training and testing
form_train <- data.frame(cbind(x_train, y_train), stringsAsFactors = F, row.names = dat_train$id)
form_test <- data.frame(cbind(x_test, y_test), stringsAsFactors = F, row.names = dat_test$id)

# Quick  test
# rf_grid <- expand.grid(mtry = c(10, 25, 50, 75, 100, 125, 150, 175, 200),
#                        splitrule = c("gini", "extratress")
#                        min.node.size = c(1,3,5))

rf <- train(
  x = df_train,
  y = y_train,
  method = "ranger",
  metric = "ROC",
  trControl = trainControl(method = "repeatedcv", number = 10,
                           repeats = 3,
                           verboseIter = T, classProbs = T,
                           savePredictions = "final"),
  # tuneGrid = tgrid,
  num.trees = 1000,
  # respect.unordered.factors = FALSE,
  verbose = TRUE,
  preProcess = c("center", "scale"),
  importance = "permutation") 

# Confusion matrix
getTrainPerf(rf) # Training set accuracy is 82% for random forest
saveRDS(rf, "data/machine_learning/models/20200105_rf_10foldcv.rds")

# Try prediction
rf$bestTune$splitrule
rf$bestTune$mtry
rf$bestTune$min.node.size



rf_ml <- ranger(y_train ~., data = form_train, num.trees = 1000, splitrule = as.character(rf$bestTune$splitrule),
                mtry = rf$bestTune$mtry, min.node.size = rf$bestTune$min.node.size,
                importance = "permutation", probability = T)

rf_pred <- predict(rf, newdata = form_test)

cm_rf <- confusionMatrix(rf_pred, as.factor(dat_test$is_active))
cm_rf # 80.22% test set accuracy


sink("output/machine_learning/20200105_rf_binary_classification_results.txt")
cm_rf
sink()

vimp <- data.frame(cbind(sort(rf_ml$variable.importance, decreasing = T),
                         names(sort(rf_ml$variable.importance, decreasing = T))), stringsAsFactors = F) %>%
  dplyr::rename(importance = X1,
                variable = X2) %>%
  mutate(importance = as.numeric(importance)) %>%
  dplyr::slice(1:15)
vimp

#pdf("output/machine_learning/random_forest_12angstroms_activity_binary_classification_vimp.pdf", width = 6, height = 6)
ggplot(data = vimp,
       aes(x=reorder(variable,importance), y=importance, fill=importance))+
  geom_bar(stat="identity", position="dodge")+ coord_flip()+
  ylab("Variable Importance")+
  xlab("")+
  guides(fill=F)+
  scale_fill_gradient(low="red", high="blue")
#dev.off()

###Naive Bayes method
#nb_grid <- expand.grid(usekernel = TRUE, fL = 0, adjust = 1)

nb <- train(
  x = df_train, 
  y = y_train,
  method = "nb",
  #tuneGrid = nb_grid,
  preProcess = c("center", "scale"),
  metric = "ROC",
  trControl = trainControl(method = "repeatedcv", number = 10, 
                           repeats = 3,
                           verboseIter = T, classProbs = T,
                           savePredictions = "final"))

# Confusion matrix
getTrainPerf(nb) # Only 59% training accuracy with NB
nb$bestTune


nb$results

nb_pred <- predict(nb, newdata = form_test)
nb$bestTune
cm_nb <- confusionMatrix(nb_pred, as.factor(dat_test$is_active))
cm_nb

sink("output/machine_learning/20200105_nb_activity_binary_classification_results.txt")
cm_nb
sink()

saveRDS(nb, "data/machine_learning/models/20200105_nb_10foldcv.rds")


## Make a heatmap of confusion matrix results
cm_list <- list(cm_nb$table)
names(cm_list) <- c("nb_aa")

pllist <- list()
for(i in 1:length(cm_list)) {
  pllist[[i]] <- ggplot(data.frame(cm_list[[i]]), aes(Prediction, Reference)) +
    geom_tile(aes(fill = Freq)) + 
    geom_text(aes(label = round(Freq, 1))) +
    scale_fill_gradient(low = "white", high = "red") +
    ggtitle(names(cm_list)[i]) +
    theme(axis.text.x = element_text(angle = 90), 
          axis.title.x = element_blank())
}

pllist[[1]]
# ggsave("output/machine_learning/nb_12angstroms_activity_binary_classification_matrix_20200102.jpeg", height=7, width=7, units='in')

###Neural networks using nnet
# Currently throws an error
nnet_grid <- expand.grid(.decay = c(0.5, 0.1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7),
                         .size = c(3, 5, 10, 20))

nnet_mod <- train(
  x = df_train,
  y = y_train,
  metric = "ROC",
  method = "nnet",
  MaxNWts = 1000000000,
  # size = 1,
  tuneGrid = nnet_grid,
  preProcess = c("center", "scale"),
  trControl = trainControl(method = "repeatedcv", repeats = 3,
                           number = 10,
                           verboseIter = T,
                           savePredictions = "final",
                           classProbs = TRUE))

# Confusion matrix
nnet_mod$bestTune
getTrainPerf(nnet_mod)

vimp <- data.frame(cbind(sort(nnet_mod$variable.importance, decreasing = T),
                         names(sort(rf_ml$variable.importance, decreasing = T))), stringsAsFactors = F) %>%
  dplyr::rename(importance = X1,
                variable = X2) %>%
  mutate(importance = as.numeric(importance)) %>%
  dplyr::slice(1:15)
vimp
saveRDS(nnet_mod, "data/machine_learning/models/20200105_nnet_10foldcv.rds")


# size decay
#  10 0.5

# approx_roc_curve(nnet_ml, "Neural network") %>%
#   ggplot(aes(x = 1 - specificity, y = sensitivity)) +
#   geom_path()  +
#   geom_abline(col = "red", alpha = .5)

nnet_pred <- predict(nnet_mod, newdata = form_test)
cm_nnet <- confusionMatrix(nnet_pred, as.factor(dat_test$is_active))
cm_nnet # 79% training accuracy

sink("output/machine_learning/20200105_nnet_binary_classification_results.txt")
cm_nnet
sink()
# dtl_feat_select <- data.frame(round(cm_nnet$byClass[,colnames(cm_nnet$byClass) %in% c("Precision", "Recall", "Balanced Accuracy")], 2))

## Make a heatmap of confusion matrix results
cm_list <- list(cm_nnet$table)
names(cm_list) <- c("nnet_aa_34")

pllist <- list()
for(i in 1:length(cm_list)) {
  pllist[[i]] <- ggplot(data.frame(cm_list[[i]]), aes(Prediction, Reference)) +
    geom_tile(aes(fill = Freq)) + 
    geom_text(aes(label = round(Freq, 1))) +
    scale_fill_gradient(low = "white", high = "red") +
    ggtitle(names(cm_list)[i]) +
    theme(axis.text.x = element_text(angle = 90), 
          axis.title.x = element_blank())
}

pllist[[1]]
ggsave("output/machine_learning/20200105_nnet_binary_classification_matrix.jpeg", height=7, width=7, units='in')

