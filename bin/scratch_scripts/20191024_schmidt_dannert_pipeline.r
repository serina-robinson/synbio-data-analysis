# Install packages
pacman::p_load("tidyverse", "readxl", "randomcoloR", "RColorBrewer", "ggplot2", "data.table", "chron")

# Set working directory
setwd("~/Documents/University_of_Minnesota/Wackett_Lab/github/synbio-data-analysis/")

### Fill in your parameters of interest ###
# cmpnd <- "TMA"
# cmpnd <- "dodecanoate"
cmpnd <- "benzoate"
# date <- Sys.Date()
date <- 2019-10-18
date

# Read in the plate template
temp <- read_excel("data/Plate Set up SynBio Paper.xlsx", skip = 3) %>%
  janitor::clean_names() %>%
  dplyr::select(-x1, -x11, -x12) %>% # NOTE THAT X11 WILL BE FILLED 
  as.matrix() %>%
  #t %>%
  as.vector()
temp

# Get file names
tmafils <- list.files("data/", pattern = cmpnd, full.names = T)
tmafils <- tmafils[!grepl("~", tmafils)] # remove any temporary files


## Need to apply to both plates
#### Apply normalize_all to the complete file names
normalize_all_txt <- function(x) { 
  raw <- x %>%
    janitor::clean_names() %>%
    #dplyr::select(-temperature_c) %>% # remove temp
    #dplyr::select_if(~ !any(is.na(.))) %>% # remove NAs
    dplyr::select_if(!grepl("v2|v13|v14|v15|v16", colnames(.))) %>%
    dplyr::filter(v3 != "") %>%
    dplyr::mutate(time = sort(rep(as.POSIXct((unique(v1)[unique(v1) != ""]), format = "%M:%S"), 8))) %>%
    dplyr::select(-v1)
  
  raw_long <- melt(raw, id = "time") %>%
    arrange(time) %>%
    dplyr::mutate(nams = rep(temp, nrow(.)/length(temp)))
  
  oleA <- read_csv("data/72_OleA_masterwell_org_key.csv")
  
  dat0 <- left_join(raw_long, oleA, 
                    by = c("nams" = "master_well")) %>%
    dplyr::mutate(variable = case_when(is.na(orgs) ~ nams,
                                       TRUE ~ orgs)) %>%
    dplyr::select(time, value, variable) %>%
    dplyr::mutate(value = as.numeric(value))
  
  ## TODO: average 3 Pet28s
  pet28 <- dat0 %>%
    dplyr::filter(grepl("Pet28", variable)) %>%
    select(value) %>%
    pull()
  
  # Remove pNP standards
  dat1 <- dat0 %>%
    dplyr::filter(!grepl("pNP", variable))
  
  pnp_rem <- dat0 %>% 
    dplyr::filter(grepl("pNP", variable))
  
  # Subtract the pET 28b+ empty vector control
  norm_pet <- function(x, na.rm = FALSE) (x - pet28)
  
  dat <- dat1 %>%
    mutate_at(c("value"), norm_pet) %>%
    bind_rows(pnp_rem)
  
  return(dat)
}

# Normalize all
rep1 <- fread(tmafils[1], fill = T, header = F, skip = 1, nrows = 405, data.table = F)
rep2 <- fread(tmafils[2], fill = T, header = F, skip = 18, nrows = 549, data.table = F)
res <- lapply(list(rep1, rep2), normalize_all_txt)


head(res[[1]])
head(res[[2]])
cbind(res[[1]]$value,res[[2]]$value)
table(res[[1]]$value == res[[2]]$value) # check values are different

# Merge the two datasets
resbind <- res[[1]] %>%
  bind_rows(res[[2]])


# Now normalize to the pNP standard curve
pNPs <- resbind %>% 
  dplyr::filter(grepl("pNP", variable)) %>%
  #dplyr::filter(!grepl(max(time), time)) %>%
  dplyr::mutate(µL = as.numeric(word(variable, sep = " ", 1))) %>%
  dplyr::mutate(mM = µL * (4/200)) %>% # 4 mM stock solution, 200 µL final well volume
  dplyr::mutate(nM = mM * 1000) %>%
  dplyr::mutate(nmol = nM * (1/1000) * (1/1000) * 200) %>% # nmoles = nmoles/L * 1L/1000 mL * 1ml/1000µL * 200 µL (final volume)
  dplyr::filter(time == min(time)) # only do minimum time for simplicity
pNPs[pNPs$variable == "10 uL pNP",]
pNPs
pNP_fit <- lm(value ~ nmol, data = pNPs)
pNP_fit$coefficients


# Plot the standard curve
pdf(paste0("output/", date, "_", cmpnd, "_standard_curve.pdf"))
pl <- ggplot(pNPs,  aes(x = nmol, y = value)) + 
  geom_point() +
  geom_smooth(method = "lm") +
  labs(y="Absorbance (410 nm)", x="nmol pNP") +
  #geom_errorbar(aes(ymax=mean + sd, ymin = mean - sd), width=0.3,size=0.6)+
  theme(legend.title=element_blank(), axis.line=element_line(color="black"),
        panel.grid.major=element_blank(),
        panel.grid.minor=element_blank(),
        panel.border=element_blank(),
        panel.background=element_blank(),
        text = element_text(size = 8),
        legend.key= element_rect(fill=NA, color=NA),
        legend.position="top") + 
  guides(shape = guide_legend(override.aes = list(size = 10)))
pl
dev.off()
pl

# Calculate slope and intercept of pNP standard curve
pNP_fit$coefficients
b <- pNP_fit$coefficients[1]
m <- pNP_fit$coefficients[2]

# Remove the pNPs to normalize
dat2 <- resbind #%>%
  #dplyr::filter(!grepl("pNP", variable))
head(dat2)

dat3 <- dat2 %>%
  dplyr::mutate(nmols_pNP = (value - b)/m) %>%
  group_by(variable, time) %>%
  summarise_each(funs(mean, sd), nmols_pNP) 
head(dat3)

# Standard deviation divided by mean * 100
summary(dat3$sd)
summary(dat3$mean)


# Find the 'winners' i.e. those with a final end point above -0.001
dat4 <- dat3 %>%
  dplyr::filter(grepl(max(time), time)) %>%
  dplyr::mutate(winners = case_when(grepl("pNP", variable) ~ variable,
                 TRUE ~ "inactive")) 
  # dplyr::mutate(winners = case_when(mean > -0.0007 ~ variable)) %>%
  # dplyr::mutate(winners = case_when(is.na(winners) ~ "inactive",
  #                                   TRUE ~ as.character(winners)))
tofind <- dat4$winners[dat4$winners != "inactive"] # 9 winners
tofind

dat5 <- dat3 %>%
  dplyr::mutate(winners = case_when(variable %in% tofind ~ as.character(variable),
                                    TRUE ~ "inactive")) %>%
  dplyr::filter(time != "2019-10-25 00:01:00")
dat5
# pal2 <- distinctColorPalette(length(unique(dat4$winners)))
#rawpal <- read_csv("data/OleA_palette_key.csv")
#pal <- rawpal$pal2[!rawpal$pal2 %in% c("seagreen1", "cyan3", "gold1", "wheat3", "orchid1", "blueviolet", "#7B6E4F")]
pal <- colorRampPalette(brewer.pal(8,"Set1"))(8)
pal2 <- c("gray80", "dodgerblue", pal[c(1, 3:5, 8)], "blue", "gold1", "black", "wheat3",)
length(pal2)

pdf(paste0("output/", date, "_", cmpnd, "_JGI_genes_without_errorbars_normalized.pdf"), width = 16, height = 14)
pl <- ggplot(dat5, aes(x=time, y=mean, color=winners)) +
  geom_point() +
  labs(y = "nmol pNP", x = "Time (minutes)") +
  #geom_errorbar(aes(ymax=mean + sd, ymin = mean - sd), width=0.3,size=0.6)+
  theme(legend.title=element_blank(), axis.line=element_line(color="black"),
        panel.grid.major=element_blank(),
        panel.grid.minor=element_blank(),
        panel.border=element_blank(),
        panel.background=element_blank(),
        text = element_text(size = 20),
        legend.key= element_rect(fill=NA, color=NA),
        legend.position="top") + 
  guides(shape = guide_legend(override.aes = list(size = 10))) +
  scale_color_manual(values=pal2) 
pl
dev.off()

pdf(paste0("output/", date, "_", cmpnd, "_JGI_genes_with_errorbars_normalized.pdf"), width = 16, height = 14)
pl <- ggplot(dat5, aes(x=time, y=mean, color=winners)) +
  geom_point() +
  labs(y = "nmol pNP", x = "Time (minutes)") +
  geom_errorbar(aes(ymax=mean + sd, ymin = mean - sd), width=0.3,size=0.6)+
  theme(legend.title=element_blank(), axis.line=element_line(color="black"),
        panel.grid.major=element_blank(),
        panel.grid.minor=element_blank(),
        panel.border=element_blank(),
        panel.background=element_blank(),
        text = element_text(size = 20),
        legend.key= element_rect(fill=NA, color=NA),
        legend.position="top") + 
  guides(shape = guide_legend(override.aes = list(size = 10))) +
  scale_color_manual(values=pal2) 
pl
dev.off()
