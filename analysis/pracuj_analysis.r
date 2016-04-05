# set working directory
# setwd("/home/krzysztof/projects/pracuj/analysis")

# import packages
library(dplyr)
library(tidyr)
library(maptools)
library(rgeos)
library(SmarterPoland) # contains ggplot2
library(portfolio)

# read data to analyze
df <- read.csv("../Filtr/pracuj_filtered.csv",
               stringsAsFactors=F, fileEncoding="WINDOWS-1250")

# leave only unique offers
pracuj <- df %>%
 filter(!duplicated(id))

# In location parameter abroad jobs contain either only country's name
# or "city, country" structure. Need to separate them from polish offers which
# mostly have "city, province" structure. Sometimes it is only province,
# couple of cities in one province (e.g. "Gdańsk, Gdynia, Sopot, pomorskie")
# or bunch of towns from across the country.

# vector of all europan countires
euro <- c("Albania", "Andora", "Anglia", "Austria", "Belgia", "Białoruś",
          "Bośnia i Hercegowina", "Bułgaria", "Chorwacja", "Cypr",
          "Czarnogóra", "Czechy", "Dania", "Estonia", "Finlandia", 
          "Francja", "Gibraltar", "Grecja", "Gruzja", "Hiszpania",
          "Holandia", "Irlandia", "Islandia", "Kazachstan", "Liechtenstein",
          "Litwa", "Luksemburg", "Łotwa", "Macedonia", "Malta", "Monako",
          "Mołdawia", "Niemcy", "Norwegia", "Polska", "Portugalia", "Rosja",
          "Rumunia", "San Marino", "Serbia", "Szwajcaria", "Szwecja",
          "Słowacja", "Słowenia", "Turcja", "Ukraina", "Watykan",
          "Wielka Brytania", "Węgry", "Włochy")

# find abroad jobs
inlist <- lapply(euro, function(x) {grep(x, pracuj$location)})

# separate abroad jobs indexes
abjob <- c()
for (i in 1:length(inlist)) {
  if (length(inlist[[i]]) != 0) {
    abjob <- append(abjob, inlist[[i]])
  }
}

# --- FOREIGN OFFERS --- #

# filter abroad positions
foreign <- pracuj[abjob, ]

# paste "NA, " into foreign positions without cities
# for later column separation
for (i in 1:length(foreign$location)) {
  if (!grepl(", ", foreign$location[i])) {
    foreign$location[i] <- paste0(NA, ", ", foreign$location[i])
  }
}

# separate foreign locations to c(city, country) structure, convert NA strings
foreign <- foreign %>%
  separate(location, c("city", "country"), sep=", ", convert=T)

# substitute doubled country names in city column with NA
for (i in 1:length(foreign$city)) {
  if(foreign$city[i] %in% euro) {
    foreign$city[i] <- NA
  }
}

# --- POLISH OFFERS --- #

# filter polish positions, take 
polish <- pracuj[-abjob, ]

# get multiple cities positions
mulCit <- polish %>%
  filter(grepl(",.*,", polish$location))

# erase them from data.frame
polish <- polish[-grep(",.*,", polish$location), ]

# split strings into cities and porvinces
citiesProv <- strsplit(mulCit$location, ", ")

# paste "NA, " into polish positions without cities for later column separation
for (i in 1:length(polish$location)) {
  if (!grepl(", ", polish$location[i])) {
    polish$location[i] <- paste0(NA, ", ", polish$location[i])
  }
}

# separate polish locations to c(city, province) structure, convert NA strings
polish <- polish %>%
  separate(location, c("city", "province"), sep=", ", convert=T)

# change location column name to province
# add fake city column to multiple cities positions
fakeCol <- which(names(mulCit) == "location")
names(mulCit)[fakeCol] <- "province"
mulCit <- cbind(mulCit[, 1:(fakeCol - 1)],
                city = rep(0, nrow(mulCit)),
                mulCit[, (fakeCol):length(names(mulCit))])

# append multiple cities positions as single rows
for (i in 1:length(citiesProv)) {
  for (j in 1:(length(citiesProv[[i]]) - 1)) {
    polish[nrow(polish) + 1, ] <- mulCit[i, ]
    polish$city[nrow(polish)] <- citiesProv[[i]][j]
    polish$province[nrow(polish)] <- citiesProv[[i]][length(citiesProv[[i]])]
  }
}

# --- MAP --- #

# read provinces shapes data
shp <- readShapePoly("POL_adm_shp/POL_adm1.shp")

# vector of provinces in order as they appear in shp@data$VARNAME_1
provinces <- c("łódzkie", "świętokrzyskie", "wielkopolskie",
               "kujawsko-pomorskie", "małopolskie", "dolnośląskie",
               "lubelskie", "lubuskie", "mazowieckie", "opolskie", "podlaskie",
               "pomorskie", "śląskie", "podkarpackie", "warmińsko-mazurskie",
               "zachodniopomorskie")

# substitute to names with polish signs
shp@data$VARNAME_1 <- provinces

# fortify data
shpf <- fortify(shp, region="VARNAME_1")

# PROVINCES

# create data.frame for map filling
offersPerProvince <- data.frame(table(polish$province), stringsAsFactors=F)
names(offersPerProvince) <- c("province", "n")

# CITIES

# create data.frame for map filling
offersPerCity <- data.frame(table(polish$city), stringsAsFactors=F)
names(offersPerCity) <- c("city", "n")

# read cities geographical coordinates
citiesGC <- read.csv("citiesGC.csv",
                     stringsAsFactors=F, fileEncoding="WINDOWS-1250")

# merge data.frames
offersPerCity <- merge(offersPerCity, citiesGC, all.x=T)

# get missing coordinates, update data and save it
if (sum(is.na(offersPerCity$lat)) != 0) {
  for (i in which(is.na(offersPerCity$lat))) {
    coords <- getGoogleMapsAddress(street="",
                                   city=offersPerCity$city[i])
    offersPerCity$lat[i] <- coords[1]
    offersPerCity$long[i] <- coords[2]
  }

  offersPerCity %>%
  select(-n) %>%
  rbind(citiesGC) %>%
  unique() %>%
  arrange(city) %>%
  write.csv("citiesGC.csv", row.names=F, fileEncoding="WINDOWS-1250")
}

# create data.frame with coordinates for jitter plot
offersJittered <- polish %>%
  filter(!is.na(city)) %>%
  merge(offersPerCity, all.x=T) %>%
  select(city, employer, lat, long) #%>%
#  mutate(city = factor(city, levels=rev(levels(factor(city)))),
#         company = factor(employer, levels=rev(levels(factor(employer))))) %>%
#  select(-employer)
names(offersJittered)[2] <- "company"

# cut data
#offersPerCity <- offersPerCity %>%
#  mutate(interval = cut(offersPerCity$n,
#                        c(0, 1, 10, 50, 100, 200, 300, max(offersPerCity$n))))
#levels(offersPerCity$interval)[1] <- 1

# COMPANIES

# create data.frame for map filling
offersPerCompany <- data.frame(table(polish$employer), stringsAsFactors=F)
names(offersPerCompany) <- c("company", "n")

offersVsCompanies <- offersPerCompany %>%
  group_by(n) %>%
  summarise(companies = n_distinct(company))

# TREE MAP

# group data by province and city, summarise employers and offers
treeData <- polish %>%
  filter(complete.cases(.)) %>%
  select(employer, city, province) %>%
  group_by(province, city) %>%
  summarise(nEmp = n_distinct(employer),
            nOff = n())

# CITY COMPANIES FOR SHINY

# group data by city and company
offersCityCompany <- polish %>%
  select(employer, city) %>%
  group_by(city, employer) %>%
  summarise(n = n()) %>%
  as.data.frame() %>%
  filter(complete.cases(.))
names(offersCityCompany)[2] <- "company"

# data for city selection
selectCity <- polish %>%
  select(employer, city) %>%
  group_by(employer, city) %>%
  summarise(n = n()) %>%
  as.data.frame() %>%
  merge(polish) %>%
  select(employer, city, n) %>%
  filter(complete.cases(.))
names(selectCity)[1] <- "company"

# PLOTS

# province plot
provinceMap <- ggplot() +
  # fill by number of offers
  geom_map(data=offersPerProvince,
           aes(map_id=province, fill=n),
           map=shpf) +
  # map contours
  geom_path(data=shpf,
            aes(x=long, y=lat, group=id),
            color="black", size=0.25) +
  # mercator projection
  coord_map(projection="mercator") +
  # change theme
  theme_bw() +
  # change fill name and color
  scale_fill_gradient("Liczba ofert", low = "grey90", high = "black") +
  # remove unnecessary elements
  theme(axis.ticks=element_blank(), panel.border=element_blank(),
        axis.text=element_blank(), panel.grid=element_blank(),
        axis.title=element_blank()) +
  # add title
  ggtitle("Ile ofert w województwie?")

# city plot
cityMap <- ggplot(offersPerCity, aes(x=long, y=lat, size=n)) +
  # color by number of offers
  geom_point(alpha=0.5) +
  # cities names
  geom_text(data=offersPerCity[offersPerCity$n > 100, ],
            aes(label=city), hjust=-0.2, size=4, show.legend=F) +
  # map contours
  geom_path(data=shpf,
            aes(group=id),
            color="black", size=0.25) +
  # mercator projection
  coord_map(projection="mercator") +
  # change theme
  theme_bw() +
  # change size scale
  scale_size_continuous(
    "Liczba ofert",
    breaks=c(0, 1, 10, 50, 100, 200, 300, max(offersPerCity$n)),
    trans="sqrt") +
  # change fill name and color
  scale_color_brewer("Liczba ofert", palette="Dark2") +
  # remove unnecessary elements
  theme(axis.ticks=element_blank(), panel.border=element_blank(),
        axis.text=element_blank(), panel.grid=element_blank(),
        axis.title=element_blank(), legend.key=element_blank()) +
  # add title
  ggtitle("Ile ofert w mieście?")

# city jittered plot
cityMapJitter <- ggplot(offersJittered, aes(x=long, y=lat)) +
  # visualise data
  geom_jitter(width=0.5, height=0.5, alpha=0.2) +
  # map contours
  geom_path(data=shpf,
            aes(group=id),
            color="black", size=0.25) +
  # mercator projection
  coord_map(projection="mercator") +
  # change theme
  theme_bw() +
  # change fill name and color
  scale_color_brewer("Liczba ofert", palette="Dark2") +
  # remove unnecessary elements
  theme(axis.ticks=element_blank(), panel.border=element_blank(),
        axis.text=element_blank(), panel.grid=element_blank(),
        axis.title=element_blank(), legend.key=element_blank()) +
  # add title
  ggtitle("Koncentracja ofert")

# city dotplot
cityDot <- ggplot(offersJittered, aes(x=0, y=city)) +
  # visualise data
  geom_dotplot(binaxis="y", method="histodot", stackdir="center", dotsize=0.1)

# company dotplot
companyDot <- ggplot(offersJittered, aes(x=0, y=company)) +
  # visualise data
  geom_dotplot(binaxis="y", method="histodot", stackdir="center", dotsize=0.1)

# company plot
companyScatter <- ggplot(offersVsCompanies, aes(x=companies, y=n)) +
  # visualize data
  geom_point() +
  # company with most offers
  geom_text(data=offersPerCompany[which.max(offersPerCompany$n), ],
            aes(x=1, y=n, label=company), hjust=-0.1) +
  # scale axes
  scale_x_log10("Liczba firm", breaks=c(1, 2^(1:10))) +
  scale_y_continuous("Liczba ofert", breaks=c(1, seq(5, 100, 5))) +
  # remove unnecessary elements
  theme(panel.grid.minor.x=element_blank()) +
  # add title
  ggtitle("Ile firm złożyło konkretną liczbę ofert?")

# plots
provinceMap
cityMap
cityMapJitter
# cityDot useless
# companyDot useless
companyScatter

# treemap plot
source("my_tree.R")
treeMap <- my.tree(id=treeData$city, area=treeData$nEmp,
                   group=treeData$province, color=treeData$nOff,
                   lab=c("group"=T, "id"=T), main="Mapa ofert")