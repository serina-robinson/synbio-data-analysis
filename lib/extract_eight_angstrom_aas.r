extract_channel_aas <- function(query_fil) {

  # Source the external functions
  source("lib/convert_seq_15aap.r")
  
  # Read in the reference sequence
  query_fil <- "data/alignments/73_OleA_JGI_unaligned.fasta"
  query <- readAAStringSet(query_fil)
  query <- query[1]
  ref <- readAAStringSet("data/alignments/4KU5.fasta")
  names(ref) <- "4KU5"
  
  # Align the query and the reference
  alned <- AlignSeqs(c(ref, query), verbose = TRUE)
  # alned <- AAStringSet(muscle(c(ref, query), in1 = "data/A_domains_muscle.fasta", in2 = query_fil, profile = T)) # If you want to align with a profile
  query_aln <- alned[length(alned)]
  ref_aln <- alned["4KU5"]
  
  # Select all residues within 8 angstroms of S143
  # PyMOL commands
  # fetch 4KU5
  # select all res, 4KU5_A
  # select all_res within 8 of S143
  channel_a <- c(253, 258, 261, 284, 291, 292, 295, 343, 345, 349, 351, 353)
  channel_b <- c(176, 173, 172, 242, 243, 112, 111, 171, 117, 316, 203, 246)
  aa34_inds <- c(channel_a, channel_b)
  aa34_inds_adj <- aa34_inds # - 65 or something like that depending on ref

  # Exract the 34 amino acid positions
  poslist <- list()
  position = 1
  
  for(i in 1:width(ref_aln)) {
    if (substr(ref_aln, i, i) != "-") {
      if (position %in% aa34_inds_adj) {
        poslist[[i]] <- i
      }
    position = position + 1
    }
  }
  
  # Get the new indices
  new_34inds <- unlist(poslist)
  new_34inds
  
  # Get 34 aa code
  query_pos <- as.character(unlist(lapply(1:length(new_34inds), function(x) {
    substr(query_aln, new_34inds[x], new_34inds[x]) })))
  writeLines(paste0(query_pos, collapse = ""))
  
  feats <- convert_seq_15aap(query_pos)
  feats

  return(feats)
}



  