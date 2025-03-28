#!/usr/bin/env Rscript
# 
#        _           _                             _   _        _                 
#       | |         | |                           | | (_)      | |                
#  _ __ | |__  _   _| | ___   __ _  ___ _ __   ___| |_ _  ___  | |_ _ __ ___  ___ 
# | '_ \| '_ \| | | | |/ _ \ / _` |/ _ \ '_ \ / _ \ __| |/ __| | __| '__/ _ \/ _ \
# | |_) | | | | |_| | | (_) | (_| |  __/ | | |  __/ |_| | (__  | |_| | |  __/  __/
# | .__/|_| |_|\__, |_|\___/ \__, |\___|_| |_|\___|\__|_|\___|  \__|_|  \___|\___|
# | |           __/ |         __/ |                                               
# |_|          |___/         |___/
# 
#   
# nf-core/ampliseq phylogenetic tree generation
# february 2025
# sources:
# https://yulab-smu.top/treedata-book/chapter2.html
# https://yulab-smu.top/treedata-book/related-tools.html#plotly
# 

#
#   +----------------------------+
#   |  Load libraries & data     |
#   +----------------------------+
#   

message("Starting R script...")

# Import libraries 

library(dplyr)
library(tidyr)
library(data.table)
library(ggplot2)
library(ggtree)

# Set vars (rectal cancer)

# dir = "rectal_cancer"
# dada2_asv_tax = "ASV_tax.silva_138.tsv" # name changes depending on database used 
# meta_filename = "Metadata.tsv"
# condition_col = "condition"
# results_path = "/home/camilla.callierotti/microbiome/tree_annotation_script/trees/"
# msa_fasta = ""

# set vars (ampliseq test profile)

dir = "pipeline_test"
dada2_asv_tax = "ASV_tax.gtdb_R07-RS207.tsv"# (file for pipeline_test dir)
meta_filename = "Metadata.tsv"
condition_col = "treatment1"
results_path = "~/ampliseq_phylogenetic_tree/trees/"
msa_fasta = ""

# Load Newick tree

tree <- read.tree(paste0("data/",dir,"/tree.nwk"))
message("Newick tree loaded.")

# Load taxonomy_qza
# 
# taxonomy_qza <- qiime2R::read_qza(paste0("data/",dir,"/taxonomy.qza"))$data
# max_levels <- max(stringr::str_count(taxonomy_qza$Taxon, ";")) + 1
# taxonomy <- taxonomy_qza %>%
#   rename(ASV = Feature.ID, Taxonomy = Taxon) %>%
#   select(ASV, Taxonomy) %>%
#   tidyr::separate(Taxonomy, into = paste0("Rank", 1:max_levels), sep = ";", fill = "right")

# Load and prepare metadata

meta <- fread(paste0("data/",dir,"/",meta_filename))
feature <- fread(paste0("data/",dir,"/feature-table.tsv"))
asv_species <- fread(paste0("data/",dir,"/",dada2_asv_tax))

asv_species[asv_species == ""] <- NA
asv_species$taxonomy <- apply(asv_species[, c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")], 1, function(row) paste(na.omit(row), collapse = "; ")) # create taxonomy string
asv_species <- asv_species[asv_species$ASV_ID %in% tree$tip.label]
asv_species$Phylum[is.na(asv_species$Phylum)] <- "Unknown Phylum"
message("Metadata loaded and prepared.")

#
#   +--------------------+
#   |      FUNCTIONS     |
#   +--------------------+
#   

# Update tip labels with taxonomy
tip_labels_to_taxonomy <- function(tree, asv_species) {
  tree$ASV <- tree$tip.label # Keep original ASVs
  tree$tip.label <- asv_species$taxonomy[match(tree$tip.label, asv_species$ASV_ID)] # Replace labels with taxonomy
  return(tree)
}

# Revert tip labels back to ASVs
tip_labels_to_asv <- function(tree) {
  if (!"ASV" %in% names(tree)) {
    stop("The tree does not contain ASV labels. Make sure to have run update_tip_labels first.")
  }
  tree$tip.label <- tree$ASV
  return(tree)
}

#
#   +----------------------------+
#   |  TREE 1 - Basic tree       |
#   +----------------------------+
#   

# Change tip labels to ASV taxonomy

tree <- tip_labels_to_taxonomy(tree, asv_species)

# Colour tree by phylum

phyla_list <- list()
for (phylum in unique(asv_species$Phylum)) {
  taxonomies <- asv_species$taxonomy[asv_species$Phylum == phylum]
  phyla_list[[phylum]] <- taxonomies
}

# Create ggtree object

tree_coloured <- groupOTU(tree, phyla_list, 'Phylum')

t1 <- ggtree(tree_coloured, layout = 'daylight', branch.length = 'none', size = 1.5) +
  aes(color = Phylum) +
  theme(legend.position = "right", legend.text = element_text(size = 6))

message("Created first tree.")

# Save tree

ggsave(paste0(results_path,"tree_phyla.pdf"), width = 100, height = 100, units = "cm", limitsize = FALSE)
message("Saved first tree.")

#
#   +--------------------------------------------+
#   |    TREE 2 - Circular tree with heatmap     |
#   +--------------------------------------------+
#   

# Create heatmap dataframe (from feature table using ASVs for join)

feature_long <- melt(feature, id.vars = "#OTU ID", variable.name = "ID", value.name = "abundance") # reshape to long format
merged_feature <- merge(feature_long, meta[, .(ID, treatment1)], by = "ID", all.x = TRUE) # merge with treatment
merged_feature_mean <- merged_feature[, .(mean_abund = mean(abundance)), by = .(`#OTU ID`, treatment1)] # compute mean abundace for otu and treatment (not sample)
heatmap <- dcast(merged_feature_mean, `#OTU ID` ~ treatment1, value.var = "mean_abund", fill = 0)

heatmap[`#OTU ID` %in% tree$ASV] # check that all OTUs in the heatmap are in the tree and vice versa

#heatmap[, 2:3] <- lapply(heatmap[, 2:3], as.numeric)
heatmap_matrix <- as.matrix(heatmap[, -1])
rownames(heatmap_matrix) <- heatmap$`#OTU ID`

message("Created heatmap for second tree.")

# Change tip labels back to ASVs

tree <- tip_labels_to_asv(tree)

# Create ggtree object

circ <- ggtree(tree, layout = "circular", branch.length = 'none')
circ_heatmap <- gheatmap(circ, heatmap_matrix, offset=0, width=.2,
               colnames_angle=95, colnames_offset_y = .25) +
  scale_fill_gradient(low = "#C6D4F9", high = "#F1A7C2", name="Abundance")
circ_heatmap

message("Created second tree.")

# Save tree

ggsave(paste0(results_path,"tree_heatmap.pdf"), plot = circ_heatmap, width = 100, height = 100, units = "cm", limitsize = FALSE)
message("Saved second tree.")

# Convert to plotly object

plotly::ggplotly(circ) # not working for circular trees

#
#   +--------------------------------------------+
#   |  TREE 3 - Tree with evolutionary distances |
#   +--------------------------------------------+
#   

# Change tip labels to ASV taxonomy

tree <- tip_labels_to_taxonomy(tree, asv_species)

# Create ggtree object

horiz <- ggtree(tree) +
  theme_tree2() +
  geom_tiplab((label=tree$tip.label), size=3) +
  labs(caption="Evolutionary Distance")
horiz

message("Created third tree.")

# Save tree

ggsave(paste0(results_path,"tree_distances.pdf"), plot = horiz, width = 100, height = 100, units = "cm", limitsize = FALSE)
message("Saved third tree.")

# Create plotly object

plotly::ggplotly(horiz, tooltip = c("label"))

# users can change branch length stored in tree object by using rescale_tree() function provided by the treeio package

#
#   +-----------------------------+
#   |  TREE 4 - TREE W MSA - WIP  |
#   +-----------------------------+
#   


msaplot(p=ggtree(tree), fasta=paste0("data/",dir,"/",msa_fasta), window=c(150, 175))

