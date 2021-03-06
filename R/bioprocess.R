

##process bio files
## creates: bio.all (one row per legislator)
##          idname (one row per legislator/name/session
                                        # names written in multiple forms)

##FIX: Get the party/state from the page index. 


library(plyr)
library(RMySQL)
source("~/reps/CongressoAberto/R/caFunctions.R")

connect.db()

gb <- function(x) trim(toupper(gsub(".*<b>(.*)<.*b>.*","\\1",x)))

get.bio <- function(file.now) {
  id <- gsub(".*id=([0-9]+)&.*","\\1",file.now)
  text.now <- readLines(file.now,encoding="latin1")
  namelong <- gb(text.now[83])
  bdate <- text.now[grep("Nascimento",text.now)]
  birth <-trim(
               sub(".*:","",
                   text.now[84]
                   )
               )
  imagefile <- gsub(".*\"(.*)\".* width.*","\\1",text.now[grep("img",text.now)[1]])
  imagefile <- gsub(".*/(depnovos.*)&nome.*","\\1",imagefile)
  birthplace <- gb((gsub(".* - ","",birth)))
  birthdate <-  as.Date(gb(gsub(" - .*","",birth)),format="%d/%m/%Y")
  sessions <- gb(text.now[grep("Legislaturas:",text.now)[1]])
  sessions <- gsub(".*: |\\.| +","",sessions)
  ##sessions <- strsplit(sessions,",")[[1]]
  mandates <- gsub("<.*>(.*)<.*>","\\1",trim(text.now[grep("Mandatos Eletivos",text.now)[1]+5]))  
  nameshort <- gb(text.now[65])
  if (substr(nameshort,nchar(nameshort),nchar(nameshort))=="-") {
    ##no party/state info (deputies from older sessions)
    ##cat(file.now,"\n")
    nameshort <- substr(nameshort,1,nchar(nameshort)-2)
    if (is.na(mandates)) {
      ## there is no mandate info
      ##FIX?: assume the person is a deputy of the birth state
      party <- NA
      state <- substr(birthplace,nchar(birthplace)-1,nchar(birthplace))
    } else {
      ##cat(file.now,"\n")
      mandlist <- sapply(strsplit(mandates,";")[[1]],trim)
      mandlist <- mandlist[grep("Deputad[oa] Federal",mandlist)]
      mandlist <- strsplit(mandlist[length(mandlist)],",")[[1]]
      lm <- length(mandlist)    
      party <- trim(mandlist[lm])
      state <- trim(mandlist[lm-1])
    }
  } else {
    partystate <- strsplit(toupper(trim(gsub(".* - ","",nameshort))),"/")
    party <- partystate[[1]][1]
    state <- partystate[[1]][2]
    nameshort <- toupper(trim(gsub(" - .*","",nameshort)))
  }
  parties <- toupper(paste(party,";",trim(gsub("<.*>(.*)<.*>","\\1",text.now[grep("Filiações Partidárias",text.now)[1]+5]))))
  ##print(sessions)
  file.now <- gsub(".*/(DepNovos.*)","\\1",file.now)
  parties <- gsub("\t+| +|^ +|^\t+","",parties)
  mandates <- gsub("\t+| +|^ +|^\t+","",mandates)
  gc()
  data.frame(nameshort, name=namelong, partynow=party, state=state, birth=birthdate, birthplace, sessions=sessions, parties=parties , mandates,bioid=id,biofile=file.now,imagefile)
}

##to download all (uncomment this to download the file)
##system(paste("wget -nd -E -Nr -P ../data/bio/all 'http://www.camara.gov.br/internet/deputado/DepNovos_Lista.asp?fMode=1&forma=lista&SX=QQ&Legislatura=QQ&nome=&Partido=QQ&ordem=nome&condic=QQ&UF=QQ&Todos=sim'",sep=''))

index.file <- "../data/bio/all/DepNovos_Lista.asp?fMode=1&forma=lista&SX=QQ&Legislatura=QQ&nome=&Partido=QQ&ordem=nome&condic=QQ&UF=QQ&Todos=sim.html"
ll <- readLines(index.file,encoding='latin1')
ll <- gsub("\t+| +"," ",ll)
##pe <- ll[grep("[A-Z] - [A-Z]",ll)]
peloc <- grep("/[A-Z]{2}<",ll)
pe <- trim(ll[peloc])
pe <- gsub("</b>","",pe)
pe <- strsplit(pe,"/")
np <- sapply(pe,function(x) x[[1]])
uf <- sapply(pe,function(x) x[[length(x)]])
np <- strsplit(np,"-")
name <- sapply(np,function(x) trim(x[[1]]))
partido.current <- sapply(np,function(x) trim(x[[2]]))
id <- gsub(".*id=([0-9]+)&.*","\\1",ll[peloc-1])

##manual fix: there is a mistake in the camara website of the
## code of "tatico"
## we recode it here
## id[id=='108697'] <- '520630'
## system(paste("wget -nd -E -Nr -P ../data/bio/all 'http://www.camara.gov.br/internet/deputado/DepNovos_Detalhe.asp?id=108697&leg=QQ'",sep=''))

data.legis <- data.frame(bioid=id,nameindex=name,state=uf)##,partido.current=partido.current)

files.list <- dir('../data/bio/all/',pattern="DepNovos_Detalhe",full.names=TRUE)
bio.all <- lapply(files.list,get.bio)
bio.all <- do.call(rbind,bio.all)

## create a deputyid/name/session to use when merging data from
## multiple sources (this is slow and memory consuming)
idname <- with(bio.all,
               data.frame(bioid,
                          name,                         
                          nameshort,
                          ##state,
                          sessions))
idname <- merge(idname,data.legis)
bio.all <- merge(subset(bio.all,select=-state),data.legis)##,by="bioid")
idname <- ddply(idname,'bioid',
                function(x) 
                with(x,data.frame(bioid,
                                  name,
                                  nameshort,
                                  nameindex,
                                  state,
                                  sessions=strsplit(as.character(sessions),",")[[1]]
                                  )
                     ),
                .progress="text")
idname <- with(idname,rbind(
                            data.frame(bioid,name=as.character(name),state,sessions),
                            data.frame(bioid,name=as.character(nameshort),state,sessions),
                            data.frame(bioid,name=as.character(nameindex),state,sessions))
               )
idname <- unique(idname)
idname$id <- ""



connect.db()


dbRemoveTable(connect,"br_bioidname")
dbRemoveTable(connect,"br_bio")

dbWriteTable(connect, "br_bioidname", idname, overwrite=TRUE,
             row.names = F, eol = "\r\n" )    

dbWriteTable(connect, "br_bio", bio.all, overwrite=TRUE,
             row.names = F, eol = "\r\n" )    


connect.db()

##manual fixes
source("~/reps/CongressoAberto/R/caFunctions.R")
connect.db()


## PHILEMON RODRIGUES was a deputy both in MG and in PB
dbSendQuery(connect,"update br_bioidname set state='PB' where (bioid='98291')")
dbSendQuery(connect,"update br_bioidname set state='MG' where (bioid='98291') AND (sessions!='2003-2007')")
dbGetQuery(connect,"select * from  br_bioidname where bioid='98291'")


##tatico deputi in both DF and GO
dbSendQuery(connect,"update br_bioidname set state='DF' where (bioid='108697') AND (sessions='2003-2007')")
dbSendQuery(connect,"update br_bioidname set state='GO' where (bioid='108697') AND (sessions='2007-2011')")
dbGetQuery(connect,"select * from  br_bioidname where bioid='108697'")

## ze indio: 100486
tmp <- iconv.df(dbGetQuery(connect,"select * from  br_bioidname where bioid='100486'"))
tmp$name <- 'JOSÉ ÍNDIO'
tmp <- unique(tmp)
dbWriteTable(connect, "br_bioidname", tmp, overwrite=FALSE,append=TRUE,
             row.names = F, eol = "\r\n" )
dedup.db('br_bioidname')


## Mainha is José de Andrade Maia Filho 182632
tmp <- iconv.df(dbGetQuery(connect,"select * from  br_bioidname where bioid='182632'"))
tmp$name <- 'MAINHA'
tmp <- unique(tmp)
dbWriteTable(connect, "br_bioidname", tmp, overwrite=FALSE,append=TRUE,
             row.names = F, eol = "\r\n" )
dedup.db('br_bioidname')






##Pastor Jorge is Jorge dos Reis Pinheiro 100606
tmp <- iconv.df(dbGetQuery(connect,"select * from  br_bioidname where bioid='100606'"))

tmp$name <- 'PASTOR JORGE'
tmp <- unique(tmp)
dbWriteTable(connect, "br_bioidname", tmp, overwrite=FALSE,append=TRUE,
             row.names = F, eol = "\r\n" )
dedup.db('br_bioidname')
