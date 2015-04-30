library(methods) #to support RScript

#' SB object that encapsulates a session
#' @field artifact_loc String location pointing to the model artifact.
#' @field modelBuilt Indication for whether only a feature search was performed or a full model was created.
#' @examples
#' # Learning example
#' session = learn("titanic", getTitanicData(train = TRUE), target="survived",algorithmsWhiteList = list("RRandomForest"))
#' #session = featureSearch("titanic", getTitanicData(train = TRUE), target="survived")
#' enriched = session$enrich(getTitanicData(train = FALSE), featureCount = 10)
#' colnames(enriched)
#' predicted = session$predict(getTitanicData(train = FALSE))
#' colnames(predicted)
#' predicted[1:5,c("survived_predicted", "X_0_probability", "X_1_probability")]
#' eval = session$evaluate()
#' #session$showFeatures()
#' #session$showConfusionMatrix()
Session = setRefClass("Session",
    fields = list(
      artifact_loc = "character",
      modelBuilt = "logical"       #TODO: replace to a function call
    ),
    methods = list(
      initialize = function(artifact_loc, modelBuilt = FALSE) {
        "initializes a session using a string provided as \\code{loc}."
        artifact_loc<<- artifact_loc
        modelBuilt <<- modelBuilt
      },

      waitForProcess = function() { #TODO: number of mintues as parameter?
        "Blocking the R console until session is finished."
        serverResponded = FALSE
        i = 0
        finalStatus = repeat {
          i = i+1
#           if (i > 10 && !serverResponded) {
#             res = "Server didn't respond for too long... terminating."
#             print(res)
#             #stop(res)
#           }
          curStatus = status()
          switch (curStatus,
            "DONE" = return ("Done"),
            "NOT_ALIVE" = return ("Server is not alive"),
            "IN_PROCESS" = {serverResponded = TRUE},
            "NO_RESPONSE" = {serverResponded = FALSE}
          )
          print(paste("Session in progress... ",i))
          flush.console()
          if (i %% 6 == 0 ) {  #TODO: report status in a parsed way
            print(i)
            print(curStatus) #TODO: parse
            flush.console()
          }
          Sys.sleep(10)
        }
        return (finalStatus)
      },

      status = function() {
        "Checking the status of the session."
        statusFile = paste0(artifact_loc,"/json/status.json")
        finalStatus = if (file.exists(statusFile)){ #currently assuming that application won't crush before file is created
          serverResponded = TRUE
          curStatus = jsonlite::fromJSON(paste(readLines(statusFile, warn=FALSE), collapse=""))
          if (curStatus$evaluation == TRUE) return ("DONE")
          if (curStatus$alive == FALSE) return("NOT_ALIVE")
          return("IN_PROCESS")   #TODO: further parse status and refine to feature search, evaluation
        } else return("NO_RESPONSE")
      },

#       hasModelBuilt = function() {
#         statusFile = paste0(artifact_loc,"/json/status.json")
#         status = if (file.exists(statusFile)){ #currently assuming that application won't crush before file is created
#           statusContent = jsonlite::fromJSON(paste(readLines(statusFile, warn=FALSE), collapse=""))
#           statusContent$model
#         } else FALSE
#         return (status)
#       },

      statusException = function() {
        curStatus = status()
        if (curStatus == "IN_PROCESS") stop("Processing still didn't finish") #TODO: or more refined
        if (curStatus != "DONE") stop(paste("Session was not completed - ", curStatus))
      },

      enrich = function(data, featureCount = NA) { #TODO: change documentation
        "Returns a data frame containing the enrichedData. \\code{data} is a dataframe to be enriched."
        statusException()
        url <- paste0(getSBserverHost(),":",getSBserverPort(),"/rapi/enrich")
        print(paste("Calling:", url))
        outputPath = tempfile(pattern = "data", tmpdir = getSBserverIOfolder(), fileext = ".tsv.gz") #TODO: complement with params
        params <-list(modelPath = artifact_loc,
                      dataPath = writeToServer(data),
                      featureCount = featureCount,
                      outputPath = outputPath,
                      pathPrefix = getSBserverIOfolder())

        params = params[!is.na(params)]

        body = rjson::toJSON(params)
        res = httr::POST(url, body = body, httr::content_type_json())
        res <- jsonlite::fromJSON(txt=httr::content(res, as="text"),simplifyDataFrame=TRUE)

        finalRes = if (is.null(res$error) && !is.null(res$result) && res$result == "OK"){
          df = read.table(outputPath, header = TRUE, sep="\t")
          for(i in 1:ncol(df)){
            if (length(levels(df[[i]])) == 1 && (levels(df[[i]]) == "false" || levels(df[[i]]) == "true")) {
              df[,i] = as.logical(as.character(df[,i]))
            } else if (length(levels(df[[i]])) == 2 && (levels(df[[i]]) == c("false","true"))) {
              df[,i] = as.logical(as.character(df[,i]))
            }
          }
          df
        } else {
          message = paste("Enrichment failed: ", res$error)
          print(message)
          stop(message)
        }
        return(finalRes)
      },

      predict = function(data) { #TODO: change documentation
        "Returns prediction on a created model. \\code{data} is a dataframe to be predicted."
        statusException()
        if (!modelBuilt) stop("Prediction requires full model building using learn")
        url <- paste0(getSBserverHost(),":",getSBserverPort(),"/rapi/predict")
        print(paste("Calling:", url))
        outputPath = tempfile(pattern = "data", tmpdir = getSBserverIOfolder(), fileext = ".tsv.gz") #TODO: complement with params
        params <-list(modelPath = artifact_loc,
                      dataPath = writeToServer(data),
                      outputPath = outputPath,
                      pathPrefix = getSBserverIOfolder())

        body = rjson::toJSON(params)
        res = httr::POST(url, body = body, httr::content_type_json())
        res <- jsonlite::fromJSON(txt=httr::content(res, as="text"),simplifyDataFrame=TRUE)

        finalRes = if (is.null(res$error) && !is.null(res$result) && res$result == "OK"){
          read.table(outputPath, header = TRUE, sep="\t")
        } else {
          message = paste("Prediction failed: ", res$error)
          print(message)
          stop(message)
        }
        return(finalRes)
      },


      evaluate = function() {
        "Returns an evaluation object containing various information on the run including evaluation metric that was used, evaluation score, precision, confusion matrix, number of correct and incorrect instances, AUC information and more."
        statusException()
        if (!modelBuilt) stop("Evaluation requires full model building using learn")
        evaluationFile = paste0(artifact_loc,"/json/evaluation.json")
        evaluation = if (file.exists(evaluationFile)){
          lines = paste(readLines(evaluationFile, warn=FALSE), collapse="")
          eval = jsonlite::fromJSON(gsub("NaN", 0.0, lines),flatten = TRUE)
          writeLines(eval$evaluation$classDetails)
          eval
        } else {stop(paste("Evaluation file does not exist in ", evaluationFile))}
        return (evaluation)
      },

      features = function() {
        "Returns a dataset with top feature information"
        statusException()
        featuresFile = paste0(artifact_loc,"/reports/features.tsv")
        features = if (file.exists(featuresFile)){
          fread(featuresFile, sep="\t", header=TRUE)
        } else {stop(paste("Features file does not exist in ", featuresFile))}
        return (features)
      },

      showReport = function(report_name = NA, showInIDE = TRUE){ #confine to a specific list
        "\\code{report_name} should be one of the following: confusionMatrix, confusionMatrix_normalized, extractor, features, field, function, InputSchema, modelComparison, roc_best, roc_CV"
        validReports = c("confusionMatrix", "confusionMatrix_normalized", "extractor", "features", "field",
                         "function", "InputSchema", "modelComparison", "roc_best", "roc_CV")
        if (is.na(report_name) || ! report_name %in% validReports ) stop("Report name is not valid")
        reportsThatRequireModel = c("confusionMatrix", "confusionMatrix_normalized", "modelComparison", "roc_best", "roc_CV")
        if (!modelBuilt && report_name %in% reportsThatRequireModel) stop("This report requires full model building using learn")
        #verify model created, check if classification, file exists
        statusException() #TODO: can be more refined here per report
        htmlSource <- paste0(artifact_loc,"/reports/", report_name, ".html")
        viewer <- getOption("viewer")
        if (!is.null(viewer) && showInIDE){
          x <- paste(readLines(htmlSource, warn = F), collapse = '\n')
          temp.f <- tempfile("plot", fileext=c(".html"))
          writeLines(x, con = temp.f)
          viewer(temp.f)
        }
        else
          utils::browseURL(htmlSource)
      },

      showExtractors = function(showInIDE = TRUE){
        "Shows extractors in the IDE viewer or in the web browser."
        showReport("extractor",showInIDE)
      },
      showFeatures = function(showInIDE = TRUE){
        "Shows features in the IDE viewer or in the web browser."
        showReport("features",showInIDE)
      },
      showFields = function(showInIDE = TRUE){
        "Shows fields in the IDE viewer or in the web browser."
        showReport("field",showInIDE)
      },
      showFunctions = function(showInIDE = TRUE){
        "Shows functions in the IDE viewer or in the web browser."
        showReport("function",showInIDE)
      },
      showInputSchema = function(showInIDE = TRUE){
        "Shows the input schema in the IDE viewer or in the web browser."
        showReport("InputSchema",showInIDE)
      },

      #require model methods
      showConfusionMatrix = function(normalized = FALSE, showInIDE = TRUE){ #verify that this was a classification problem
        "Shows a confusion matrix of a model in the IDE viewer or in the web browser."
        showReport(if (normalized) "confusionMatrix_normalized" else "confusionMatrix",showInIDE)
      },
      showModelComparison = function(showInIDE = TRUE){
        "Shows cross validation of various algorithms tested to create a model in the IDE viewer or in the web browser."
        showReport("modelComparison",showInIDE)
      },
      showROC = function(showInIDE = TRUE){
        "Shows ROC of the model in the IDE viewer on in the web browser."
        showReport("roc_best",showInIDE) #problematic to show in internal browser non local resources
      },
      showROC_CV = function(showInIDE = TRUE){
        "Shows ROC of cross validation of various algorithms tested to create a model in the IDE viewer on in the web browser."
        showReport("roc_CV",showInIDE) #problematic to show in internal browser non local resources
      }
# save and load are probably more confusing at this time hence commented out. Just use regular save and load.
#       ,
#       save = function(filename) {
#         'Save the current object to \\code{filename} in R external object format.'
#         SBmodelSerializeVar = .self
#         base::save(SBmodelSerializeVar, file = filename)
#       },
#
#       load = function(filename) {
#         'Loads a saved SparkBeyond model saved using \\code{$save}. Paramter: \\code{filename} where the model was saved.'
#         base::load(filename)
#         loadedModel = SBmodelSerializeVar
#         rm(SBmodelSerializeVar)
#         return(loadedModel)
#       }

      # add columnSubSetSize
      # add customColumnSubset
      # sessionBlackList

      # add dashboard json
      # lift, regression plots
      # feature clusters report
      # featurePlots
      # add S3 methods of print, predict
  )
);




