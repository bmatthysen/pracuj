#loading libs
library("dplyr")
library("readr")
library("utils")
library("data.table")
library("lubridate")
library("RPostgreSQL")

dbname = "pracuj"
user = "pracuj"
password = "h"
host = "services.mini.pw.edu.pl"



sterownik <- dbDriver("PostgreSQL")
polaczenie <- dbConnect(sterownik, dbname = dbname, user = user, password = password, host = host)

#
#swapping dir to get some data
#setwd("../crawler")

#importing csv (to be ignored)

      # building up the filename
    
        #scanning ../crawler for names
        #f_name <- list.files("../crawler", pattern="*.csv", full.names=FALSE) %>%
    
        #extracting date from f_names in numeric format -> YYMMDD
        #gsub(pattern = "jobs\\.*\\.csv$",replacement = "", f_names) %>%
    
        #selecting latest dataset
        #max(na.rm = TRUE)

    
  # actual imported data without "NA" elements
  # pracuj_data <- read_csv("pracuj.csv" , col_names = TRUE) %>%
  # filter(position != "NA")
  pracuj_data <- dbGetQuery(polaczenie, "SELECT * FROM offers")  

  
  # switching back to filtering directory
  setwd("../Filtr")
  
  # creating dictionary forjob offers selection
  
  #created dictionaries:
  # - phrase_dic_eng.csv contains summary of phrases in english which determine if
  #   the job offer belongs to data.science category
  # - phrase_dic_pl.csv contains summary of phrases in polish which determine
  #   if the job offer belongs to data.science category
  # - exeptions_phrase_eng.csv, exeptions_phrase_pl.csv contain expressions which indicate job offer outside data.science industry
  #
  # - exeptions_words_eng.csv, exeptions_words_pl.csv -- || -- (words instead of full expressions)  
  
  
  
  # changing dir to get dicts
  setwd("dict")
  
  # listing all avaliable dictionaries
  f_dic_names <- list.files("../dict", pattern="*.csv", full.names=FALSE)

  
  
  
  dic_list <- list()
  
  
  #reading all avaliable dictionaries
  for (dic in f_dic_names) {
   
   
   dic_list_i <- read_csv(paste0(dic) , col_names = TRUE)
   dic_list <- append(dic_list, dic_list_i)  
  }
  
  # going back to ../
  setwd("../")
  
  #creating propper vector names for phrases extraction from dictionaries to vectors
  f_dic_names <- lapply(f_dic_names, function (x) {gsub(pattern = "\\.*\\.csv$",replacement = "", x)})
  
  
  # naming vector of dictionaries names
  names(dic_list) <- f_dic_names


# Propper filtering
  
# 'href' selected for filtering due to universal structure .../position-name-city
  
  

  # same ID killer
  pracuj_data <- as.data.table(pracuj_data)
  setkey(pracuj_data, id)
  pracuj_data <- pracuj_data[!duplicated(pracuj_data),]
  
  # creating vector used to filter interesting offers
  needed_complete_phrases <- unlist(dic_list[grep(pattern = ".*\\phrase_dic\\.*", names(dic_list))], use.names = FALSE)
  
  # creating vector used to filter out exeptions (offers containing "data-analyst" etc, but not in data.science industry)
  exeptions_phrases <- unlist(dic_list[grep(pattern = ".*exeptions_phrase\\.*", names(dic_list))], use.names = FALSE)
  

  # filtering according to phrases normally indicating data.science industry job   
  filtered_data <- data.frame()
  filtered_data_w_dupli <- data.frame()

  
  
  omited_data <- data.frame()
  for (NCP in needed_complete_phrases)  {
    filtered_data1 <- 0
    print(paste0(".*",NCP,".*"))
    filtered_data1 <- mutate(pracuj_data, DSIndicator = grepl(paste0(".*",NCP,".*"), href) )%>% filter(DSIndicator == TRUE)#%>%mutate(JobName = paste0(NCP)) 
    filtered_data <- rbind(filtered_data, filtered_data1)
    
    
  }
  
   
    nonDS_primarily_omited_data <- mutate(pracuj_data, DSIndicator = grepl(paste0(".*",NCP,".*"), href) )%>%filter(DSIndicator == FALSE)
    filtered_data_w_dupli <- filtered_data
    

  
  
  # excluding offers containing phrases which indicate non-data.science affiliation 
    nonDS_exeptions_omited_data <- data.frame()
  for (EP in exeptions_phrases)
  {
    filtered_data <- mutate(filtered_data, ExeptionIndicator = grepl(paste0(".*",EP,".*"), href) )
    nonDS_exeptions_omited_data1 <- filter(filtered_data, ExeptionIndicator == TRUE)
    filtered_data <-filter(filtered_data, ExeptionIndicator == FALSE)
    nonDS_exeptions_omited_data <- rbind(nonDS_exeptions_omited_data, nonDS_exeptions_omited_data1)
    }

    

  
  
  # removing "Indicators" from dataset
  filtered_data <- select(filtered_data, -contains("Indicator"))%>%arrange(desc(date))
  nonDS_primarily_omited_data <- select(nonDS_primarily_omited_data, -contains("Indicator"))%>%arrange(desc(date))
  nonDS_exeptions_omited_data <- select(nonDS_exeptions_omited_data, -contains("Indicator"))%>%arrange(desc(date))
  
  # getting dataset for number of phrases analysis ready
  filtered_data_w_dupli <- filtered_data
  
  # same ID killer
  filtered_data <- as.data.table(filtered_data)
  setkey(filtered_data, id)
  filtered_data <- filtered_data[!duplicated(filtered_data),]
  filtered_data <- as.data.frame(filtered_data)
  
  #filtering out months (only valid for 2016)
  offers_per_month <- data.frame(c(0), c(0))
  names(offers_per_month) <- c("month", "number_of_offers")
  
  ########################################################################################################
  
  # unifing date format - not needed anymore
  # filtered_data_badDate <- filter(filtered_data, description == "NULL") %>% mutate(date = dmy(date))
  # filtered_data_goodDate <- filter(filtered_data, description != "NULL" | is.na(description))
  # filtered_data <- rbind(filtered_data_badDate, filtered_data_goodDate)
  
  ########################################################################################################

  

  
  # looking for latest month in offers were posted
    last_month <- mutate(filtered_data, date = as.Date(date, "%Y-%m-%d"), my_month = format(date, "%m")) %>%
                  summarise(max(my_month))
  names(last_month) <- c("month_lim")
  # Making reference data.frame format in which number of offers per month should be stored
  month_ref_col <- c(1:last_month$month_lim)
  opm_ref_col <- c(replicate(last_month$month_lim, 0))
    
    ref_offers_per_month <- data.frame(month_ref_col, opm_ref_col)
  
  #going for JobNamesCloud dir!
  setwd("JNCdir")
  
  opm_df <- data.frame(month_ref_col, replicate(length(needed_complete_phrases), opm_ref_col))
  names_opm_df <- needed_complete_phrases
  names_opm_df <- c("month", names_opm_df)
  names(opm_df) <- names_opm_df
  offers_to_plot <- data.frame()
  offers_to_plot1 <- data.frame()
  job_name <- c()
  i <- 1
  per_month_names <- c()
  for (NCP in needed_complete_phrases)  
    {
    offers_per_month <- 0
    filtered_data1 <- 0
    job_name <- NULL
    offers_to_plot1 <- NULL
    filtered_data1 <- mutate(filtered_data, DSIndicator = grepl(paste0(".*",NCP,".*"), href) )%>% filter(DSIndicator == TRUE)#%>%mutate(JobName = paste0(NCP)) 
    offers_per_month <- mutate(filtered_data1, date = as.Date(date, "%Y-%m-%d"),year = format(date, "%Y"), my_month = format(date, "%m")) %>%
      group_by(my_month) %>%
      summarise(sum(DSIndicator))
    
      
    assign(paste0(NCP), offers_per_month)
    offers_per_month$my_month <- as.integer(offers_per_month$my_month) 
    
    
    
    for(q in 1:length(offers_per_month$my_month)){
      job_name <- c(job_name, NCP)
    }
    offers_to_plot1 <-  data.frame(offers_per_month, job_name)
    offers_to_plot <- rbind(offers_to_plot, offers_to_plot1)
    
    if (length(offers_per_month$my_month) == length(opm_df$month)) {
    opm_df[, (i+1)] <- offers_per_month$`sum(DSIndicator)`
    
    } else {
      for(n in length(offers_per_month$my_month)) {
        opm_df[(offers_per_month$my_month), (i+1)] <- offers_per_month$`sum(DSIndicator)`
      }
      
    
    }
    
    
    
    per_month_names[i] <- paste0(NCP,"_per_month")
    i <- i+1
    
  }

  #heading for home dir
 setwd("../")
  
 # Naming offers_to_plot
 names(offers_to_plot) <- c("month", "number_of_offers_per_month", "phrase")
 
  # switching digits to months
 month_names <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

 for (r in 1:length(opm_df$month)) {
   opm_df$month[r] <- month_names[r] 
   
 }
 

 
 
  
  # writing solution to files
 
  pracuj_data_with_desc <- filter(pracuj_data, !is.na(description)) %>% filter(description != "NULL") %>% filter(!is.null(description))
  write_csv(pracuj_data_with_desc, "pracuj_dataset.csv")
  
  
  write_csv(filtered_data, "pracuj_filtered.csv")
  write_csv( nonDS_exeptions_omited_data, "nonDS_exeptions_omited_data.csv")
  #write_csv(nonDS_primarily_omited_data,  "nonDS_primarily_omited_data.csv")
  write_csv(filtered_data_w_dupli, "filtered_data_w_dupli.csv")
  write_csv(opm_df, "job_names_per_month.csv")
  write_csv(offers_to_plot, "job_names_per_month_plot.csv")
  
  needed_complete_phrases <- as.data.frame(needed_complete_phrases)
  write_csv(needed_complete_phrases, "needed_complete_phrases.csv")
  
  exeptions_phrases <- as.data.frame(exeptions_phrases)
  write_csv(exeptions_phrases, "exeptions_phrases.csv")
  