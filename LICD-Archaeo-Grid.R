zz <- file("Grid_output.Rout", open="wb")
sink(zz)
sink(zz, type = "message")

# Import data from CRAN
library(archdata)
data("BarmoseI.grid")
data("BarmoseI.pp")

Easts <- sort(unique(BarmoseI.grid$East))
Norths <- sort(unique(BarmoseI.grid$North))

BarmoseI_Cores.pp <- BarmoseI.pp[BarmoseI.pp[, "Label"]=="Cores",]

library(spatstat)
BarmoseI_Cores.ppp <- ppp(BarmoseI_Cores.pp$East, BarmoseI_Cores.pp$North, window=owin(xrange=c(0, max(Easts)+1), yrange=c(0, max(Norths)+1)))
summary(BarmoseI_Cores.ppp)

# Convert to stars array
library(stars)
packageVersion("stars")
BarmoseI.grid1 <- BarmoseI.grid
if (packageVersion("stars") < "0.4.4") {
  BarmoseI.grid1$North <- BarmoseI.grid1$North + 1
} else {
  BarmoseI.grid1$North <- BarmoseI.grid1$North + 0.5
  BarmoseI.grid1$East <- BarmoseI.grid1$East + 0.5
}

# data registed to SW cell corner, stars bug 0.4-2, 0.4-3 and 0.4-4 before
# late October 2020; stars >= 0.4-2 required by current tmap;
# stars 0.4-4 installed using remotes::install_github("r-spatial/stars")
# 6 November 2020
# 
rast <- st_as_stars(BarmoseI.grid1[,c(2,1,3)])
# impose a plate carree projection to satisfy tmap
st_crs(rast) <- 32662
rast1 <- rast
rast1$logp1_Debitage <- log10(rast1$Debitage+1)

# convert to sf data.frame
library(sf)
barmose0 <- st_as_sf(rast)
barmose <- barmose0[!is.na(barmose0$Debitage),]
cores <- st_as_sf(BarmoseI_Cores.pp, coords=c("East", "North"))
# impose a plate carree projection to satisfy tmap
st_crs(cores) <- 32662

jpeg("Barmose_Grid_Check.jpeg", width=15, height=17, units="cm", res=300)
opar <- par(no.readonly=TRUE)
par(mar=c(0,0,0,0)+0.1)
plot(BarmoseI_Cores.ppp, chars=24, pt.bg="grey", cex=0.7, legend=FALSE)
abline(v=Easts, lwd=0.5, lty=2)
abline(h=Norths, lwd=0.5, lty=2)
points(North ~ East, BarmoseI.grid, pch=3)
plot(st_geometry(barmose), add=TRUE, lwd=0.5, border="orange")
par(opar)
dev.off()



library(tmap)
Log_Deb_map <- tm_shape(rast1, unit="m") + 
  tm_raster("logp1_Debitage", n=7, palette="viridis",
            title="Debitage\n(log count)") + 
  tm_shape(cores, unit="m") + tm_symbols() + 
  tm_legend(position=c("left", "bottom")) + 
  tm_scale_bar(breaks=c(0,1,2), position=c("right", "bottom"))
jpeg("Barmose_Grid_Cores.jpeg", width=15, height=17, units="cm", res=300)
Log_Deb_map
dev.off()


barmose$cores <- sapply(st_intersects(barmose, cores), length)
barmose$class <- factor((barmose$cores>0)+0, levels=c(0, 1), labels=c("No Core", "Core"))

sum(barmose$cores) # 86 for stars 0.4-4 and using sf::st_intersects
table(barmose$cores)
#  0  1  2  3  4  5  6  9 
# 69 18 11  2  2  1  3  1 
table(barmose$class)
# NC  C 
# 69 38 

class_map <- tm_shape(barmose, unit="m") + 
  tm_fill("class", palette="viridis") + 
  tm_shape(cores, unit="m") + 
  tm_symbols() + 
  tm_scale_bar(breaks=c(0,1,2), position=c("right", "bottom"))
jpeg("Barmose_class_Cores.jpeg", width=15, height=17, units="cm", res=300)
class_map
dev.off()

# Create neighbours

## Contiguity neighbours l-order, l = 3 - USE ONLY WHEN WINDOW IS LARGER THAN 1ST ORDER!

library(spdep)
nb1 <- poly2nb(barmose)
barmose.nb <- nblag(nb1, 2) ## higher orders
barmose.mat <- as(nb2listw(nblag_cumul(barmose.nb), style="B"), "CsparseMatrix")


# Join-Count Statistics
## JC for contiguity

jc.barmose <- vector(mode="list", length=length(barmose.nb))
jc.barmose.p <- vector(mode="list", length=length(barmose.nb))

for (i in 1:length(barmose.nb)) {
  jc.barmose[[i]] <- joincount.multi(barmose$class, nb2listw(barmose.nb[[i]]))
  jc.barmose.p[[i]] <- pnorm(jc.barmose[[i]][,4], lower.tail=FALSE)
}

## Exporting output

jcs <- do.call("rbind", jc.barmose)[-c(4, 8),]
jcps <- do.call("c", jc.barmose.p)[-c(4, 8)]

(jc_out <- data.frame(order=rep(c("First", "Second"), each=3), JCS=rownames(jcs), as.data.frame(cbind(jcs, pvalue=jcps)), row.names=NULL))

write.csv(jc_out, "barmose_jc_out.csv", row.names=FALSE)


###########################################
## Boots' LICD (from Boots 2003) ##
###########################################
## Set column with analysed data in datafile
clm <- "class"
adata <- factor(barmose[[clm]]) #object with "levels" (factor)

#### STEP 1: local composition
p <- (as.matrix(summary(adata)))/length(adata) #probabilities of each "type"
adata <- as.numeric(adata) #factor no longer necessary, now numeric



  ## Routine 1 ##
  # cluster has 5 columns: 1 - number of units of the "type" as the unit j in the "window
  # 2 - probability of the "type", 3 - "window" size, 4 - P(X>=x), 5 - P(X<=x)
library(Matrix)
  
c1 <- c2 <- c3 <- c4 <- c5 <- numeric(length(adata))
for (i in 1:length(adata)) {
    c1[i] <- (barmose.mat[i,] %*% ifelse(adata==2,1,0))+ifelse(adata[i]==2,1,0)
    c2[i] <- p[2]
    c3[i] <- sum(barmose.mat[i,])+1
    c4[i] <- sum(dbinom(c1[i]:c3[i], size=c3[i], prob=c2[i]))
    c5[i] <- sum(dbinom(0:c1[i], size=c3[i], prob=c2[i]))
  }
cluster <- cbind(c1, c2, c3, c4, c5)
  
  cluster[is.nan(cluster)]<- 1
  ## End of routine 1 ##
  
  ### Custer-outlier analysis -> result of local composition ###
  sc <- 1-(1-0.05)^(1/2) #Sidak correction, 0.05 level of significance
  local_comp <- ifelse(cluster[,4]< sc, 1, ifelse(cluster[,5]< sc, 0, -1))
  # 1 for black, 0 for white, -1 - black-white
  
  #### STEP 2: local configuration
  
  ## Routine 2  ##
  ## We built empirical distribution of joincounts on regular lattices##
  ## We don't have Boots data about distributions, nor Tinkler (1977)
  ## We use permutational approach
JC.pvalue_seq <- matrix(0, ncol=3, nrow=length(adata))
for (j in 1:length(adata))  {
    barmose.mat.1 <- barmose.mat[j,] #extracting a row from weights matrix
    ktore <- which(barmose.mat.1!=0, arr.ind = TRUE) #looking for neighbours of j
    barmose.1 <- barmose[c(j,ktore),] #adding j to the list of its neighbours
    barmose.1.B <- nb2listw(poly2nb(barmose.1, queen=FALSE), style="B") #weights matrix for j and its neighbours
    S0 <- Szero(barmose.1.B)
    adata01 <- barmose.1[[clm]]  #substraction data related to window
    if (any(adata01 != adata01[1])){
      #if any unit is different "type" from j, then I calculate JC
      A <- joincount.multi(as.factor(adata01), barmose.1.B)
      A[is.nan(A)]<- 1
    } else {
      A <- matrix(0,3,1)
      if (adata01[1] == 1){
        A[,1] <- c(0,S0/2,0)
      } else {
        A[,1] <- c(S0/2,0,0)
      }
    }
    JC.distrib <- cbind(A[2,1],A[1,1],A[3,1])
    
    # Building empirical distribution - using permutations
    for (s in 1:length(c(j,ktore))^2){
      vector_01 <- as.factor(sample(adata01)) # permutation of original 0-1 vector
      if (any(vector_01 != vector_01[1])){
        B <- joincount.multi(vector_01, barmose.1.B) # JC for permutation
        JC.distrib <- rbind(JC.distrib, cbind(B[2,1],B[1,1],B[3,1]))
      } else { #JC in the case where all are "0" or "1": The permutations are out of sense
        if (vector_01[1] == 1){
          JC.distrib <- rbind(JC.distrib, cbind(S0/2,0,0)) # all connections are BB or WW
        } else {
          JC.distrib <- rbind(JC.distrib, cbind(0,S0/2,0))  
        }
      }
    }
    # empirical distribution
    JC.pvalue_seq[j,] <- (1/(1+s))*cbind(length(which(JC.distrib[,1]>=A[2,1])),length(which(JC.distrib[,2]>=A[1,1])),length(which(JC.distrib[,3]>=A[3,1])))
  }
  ## End of routine 2 ##
  
  colnames(JC.pvalue_seq) <- c("1:1X>=x","0:0X>=x", "1:0X>=x")
  
  local_config <- matrix(3,length(adata),1)
  scJC <- 1-(1-0.05)^(1/3) # Sidak correction JC - 3 tests!
  #scJC <- 0.05 #standard
  
  ### Routine 3 Local configuration
  
  local_config <- matrix(nrow=length(adata), ncol=1)
for (j in 1:length(adata)) {#for black is 1, for white is 0, for black-white is -1, otherwise -2
    if (min(JC.pvalue_seq[j,])<scJC){
      ifelse(which(JC.pvalue_seq[j,]==min(JC.pvalue_seq[j,]), arr.ind = T)==1,local_config[j]<- 1,
             ifelse(which(JC.pvalue_seq[j,]==min(JC.pvalue_seq[j,]), arr.ind = T)==3,local_config[j]<- -1,
                    local_config[j]<- 0 ))
    } else {
      local_config[j]<- -2}
  }
  ## End of routine 3 ##
  colnames(local_config) <- c("cluster-dispersion")

# Combination of local composition and local configuration
Type <- character(length(adata))
C <- cbind(local_comp, local_config)
for (i in 1:length(adata)){
  ifelse(C[i,1] == 1 && C[i,2] == 1, Type[i] <- "Hot Clump",
         ifelse(C[i,1] == 1 && (C[i,2] == -2 || C[i,2] == 0), Type[i] <- "Hot only",
                ifelse(C[i,1] == 0 && (C[i,2] == -2 || C[i,2] == 1), Type[i] <- "Cold only",
                       ifelse(C[i,2] == -1, Type[i] <- "Dispersed only",
                              ifelse(C[i,1] == 0 && C[i,2] == 0, Type[i] <- "Cold clump",
                                     ifelse(C[i,1] == -1 && C[i,2] == 1, Type[i] <- "Clump only (Hot)",
                                            ifelse(C[i,1] == -1 && C[i,2] == 0, Type[i] <- "Clump only (Cold)",
                                                   Type[i] <- "No cluster")))))))
}

barmose$Type <- factor(Type)

types_map <- tm_shape(barmose, unit="m") + 
  tm_fill("Type", palette="viridis") + 
  tm_scale_bar(breaks=c(0,1,2), position=c("right", "bottom"))
jpeg("Barmose_types_Cores.jpeg", width=15, height=17, units="cm", res=300)
types_map
dev.off()



# Plot Cores + LICD - TIFF + JPEG

LICDClass <- interaction(barmose$class, barmose$Type, sep=" ")

barmose$LICDClass <- factor(LICDClass, levels=c("Core Hot only", "Core Clump only (Hot)", "Core Hot Clump", "Core No cluster", "No Core Hot only", "No Core No cluster", "No Core Cold only", "No Core Clump only (Cold)"))

LICDClass_map <- tm_shape(barmose, unit="m") + 
  tm_fill("LICDClass", palette="-viridis", title="Classes + LICD") + 
  tm_scale_bar(breaks=c(0,1,2), position=c("right", "bottom"))
jpeg("Barmose_LICD_class.jpeg", width=15, height=17, units="cm", res=300)
LICDClass_map
dev.off()

sessionInfo()
sf_extSoftVersion()
sink(type = "message")
sink()


