# HITs

as.data.frame.HITs <- function(xml.parsed, return.hit.xml = FALSE, 
    return.qual.list = TRUE, sandbox = getOption('MTurkR.sandbox')) {
    hit.xml <- xpathApply(xml.parsed, "//HIT")
    if(!is.null(length(hit.xml))) {
        quals <- list()
        HITs <- data.frame(matrix(nrow = length(hit.xml), ncol = 19))
        names(HITs) <- c("HITId", "HITTypeId", "CreationTime", 
            "Title", "Description", "Keywords", "HITStatus", 
            "MaxAssignments", "Amount", "AutoApprovalDelayInSeconds", 
            "Expiration", "AssignmentDurationInSeconds", "NumberOfSimilarHITs", 
            "HITReviewStatus", "RequesterAnnotation", "NumberOfAssignmentsPending", 
            "NumberOfAssignmentsAvailable", "NumberOfAssignmentsCompleted", 
            "Question")
        for(i in 1:length(hit.xml)) {
            q <- xpathApply(xml.parsed, "//HIT")[[i]]
            HITs[i, 1] <- xmlValue(xmlChildren(q)$HITId)
            HITs[i, 2] <- xmlValue(xmlChildren(q)$HITTypeId)
            HITs[i, 3] <- xmlValue(xmlChildren(q)$CreationTime)
            HITs[i, 4] <- xmlValue(xmlChildren(q)$Title)
            HITs[i, 5] <- xmlValue(xmlChildren(q)$Description)
            HITs[i, 6] <- xmlValue(xmlChildren(q)$Keywords)
            HITs[i, 7] <- xmlValue(xmlChildren(q)$HITStatus)
            HITs[i, 8] <- xmlValue(xmlChildren(q)$MaxAssignments)
            if(!is.null(xmlChildren(q)$Reward))
                HITs[i, 9] <- xmlValue(xmlChildren(xmlChildren(q)$Reward)$Amount)
            HITs[i, 10] <- xmlValue(xmlChildren(q)$AutoApprovalDelayInSeconds)
            HITs[i, 11] <- xmlValue(xmlChildren(q)$Expiration)
            HITs[i, 12] <- xmlValue(xmlChildren(q)$AssignmentDurationInSeconds)
            HITs[i, 13] <- xmlValue(xmlChildren(q)$NumberOfSimilarHITs)
            HITs[i, 14] <- xmlValue(xmlChildren(q)$HITReviewStatus)
            HITs[i, 15] <- xmlValue(xmlChildren(q)$RequesterAnnotation)
            HITs[i, 16] <- xmlValue(xmlChildren(q)$NumberOfAssignmentsPending)
            HITs[i, 17] <- xmlValue(xmlChildren(q)$NumberOfAssignmentsAvailable)
            HITs[i, 18] <- xmlValue(xmlChildren(q)$NumberOfAssignmentsCompleted)
            HITs[i, 19] <- xmlValue(xmlChildren(q)$Question)
            if(return.qual.list == TRUE) {
                quals.nodeset <- xpathApply(xml.parsed, paste("//HIT[", i,
                    "]/QualificationRequirement", sep = ""))
                if(!is.null(quals.nodeset) && length(quals.nodeset) > 0) {
                    quals[[i]] <- as.data.frame.QualificationRequirements(xmlnodeset = quals.nodeset, 
                                hit.number = i, sandbox = sandbox)
                    if(is.null(quals[[i]]) || is.na(quals[[i]])) {
                        quals[[i]] <- setNames(data.frame(matrix(ncol=6, nrow=0)),
                                    c('HITId','QualificationTypeId','Name',
                                    'Comparator','Value','RequiredToPreview'))
                    }
                    else
                        quals[[i]]$HITId <- HITs$HITId[i]
                }
                else {
                    quals[[i]] <- setNames(data.frame(matrix(ncol=6, nrow=0)),
                                    c('HITId','QualificationTypeId','Name',
                                    'Comparator','Value','RequiredToPreview'))
                }
            }
        }
        if(!is.null(quals))
            return(list(HITs = HITs, QualificationRequirements = quals))
        else
            return(list(HITs = HITs))
    }
    else
        return(list(HITs = NULL))
}


# ASSIGNMENTS

as.data.frame.Assignments <- function(xml.parsed, return.assignment.xml = FALSE) {
    assignments <- xpathApply(xml.parsed, "//Assignment", function(x){
        children <- xmlChildren(x)
        return(list(
            AssignmentId = xmlValue(children$AssignmentId),
            WorkerId = xmlValue(children$WorkerId),
            HITId = xmlValue(children$HITId),
            AssignmentStatus = xmlValue(children$AssignmentStatus),
            AutoApprovalTime = xmlValue(children$AutoApprovalTime),
            AcceptTime = xmlValue(children$AcceptTime),
            SubmitTime = xmlValue(children$SubmitTime),
            ApprovalTime = xmlValue(children$ApprovalTime),
            RejectionTime = xmlValue(children$RejectionTime),
            RequesterFeedback = xmlValue(children$RequesterFeedback),
            Answer = xmlValue(children$Answer)
        ))
    })
    assignments <- do.call(rbind.data.frame, assignments)
    assignments$HITId <- xmlValue(xpathApply(xml.parsed, 
            paste("//HITId", sep = ""))[[1]])
    assignments$ApprovalRejectionTime <-
        ifelse(!is.na(assignments$ApprovalTime),
            assignments$ApprovalTime, assignments$RejectionTime)
    assignments$SecondsOnHIT <- as.double(strptime(assignments$SubmitTime, 
            format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) - 
            as.double(strptime(assignments$AcceptTime, 
              format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))

    # return answers and merge
    answers <- as.data.frame.QuestionFormAnswers(xml.parsed = xml.parsed)
    values <- reshape(answers, timevar="QuestionIdentifier",
                    direction="wide", idvar="AssignmentId",
                    drop=c( "WorkerId","HITId","FreeText","SelectionIdentifier",
                            "OtherSelectionField","UploadedFileKey","UploadedFileSizeInBytes"))
    names(values) <- gsub("Combined.Answers.","",names(values),fixed=TRUE)
    assignments <- merge(assignments,values,by="AssignmentId",all=TRUE)
    return(list(assignments = assignments, answers = answers))
}




# QUALIFICATION STRUCTURES

as.data.frame.QualificationRequirements <- function (xml.parsed = NULL, xmlnodeset = NULL, hit = NULL, 
    hit.number = NULL, sandbox = getOption('MTurkR.sandbox')){
    if(is.null(xmlnodeset) & is.null(xml.parsed)) 
        stop("Must supply XML (parsed or unparsed) xor XMLNodeSet")
    batch <- function(xmlnodeset) {
        quals <- setNames(data.frame(matrix(nrow = length(xmlnodeset), ncol = 6)),
                    c("HITId", "QualificationTypeId", "Name",
                    "Comparator", "Value", "RequiredToPreview"))
        for(i in 1:length(xmlnodeset)) {
            quals$QualificationTypeId[i] <- xmlValue(xmlChildren(xmlnodeset[[i]])$QualificationTypeId)
            if(quals$QualificationTypeId[i] %in% ListQualificationTypes()$QualificationTypeId) {
                qlist <- ListQualificationTypes()
                quals$Name[i] <- qlist[qlist$QualificationTypeId == 
                  quals$QualificationTypeId[i], "Qualification"]
            } else
                quals$Name[i] <- NA
            quals$Comparator[i] <- xmlValue(xmlChildren(xmlnodeset[[i]])$Comparator)
            if("LocaleValue" %in% names(xmlChildren(xmlnodeset[[i]]))) 
                quals$Value[i] <- xmlValue(xmlChildren(xmlnodeset[[i]])$LocaleValue)
            if("IntegerValue" %in% names(xmlChildren(xmlnodeset[[i]]))) 
                quals$Value[i] <- xmlValue(xmlChildren(xmlnodeset[[i]])$IntegerValue)
            quals$RequiredToPreview[i] <- xmlValue(xmlChildren(xmlnodeset[[i]])$RequiredToPreview)
        }
        return(quals)
    }
    if(!is.null(xmlnodeset))
        return(batch(xmlnodeset))
    else if(!is.null(xml.parsed)) {
        if(!is.null(hit.number)) 
            xmlnodeset <- xpathApply(xml.parsed, paste("//HIT[", 
                hit.number, "]/QualificationRequirement", sep = ""))
        else if(is.null(hit.number)) 
            xmlnodeset <- xpathApply(xml.parsed, "//QualificationRequirement")
        if(!is.null(xmlnodeset)) 
            return(batch(xmlnodeset))
        else
            return(NULL)
    } else if(!is.null(hit)) {
        xmlnodeset <- xpathApply(xmlParse(GetHIT(hit = hit, keypair = credentials, sandbox = sandbox)$xml), 
            paste("//QualificationRequirement", sep = ""))
        return(batch(xmlnodeset))
    } else
        return(NULL)
}


as.data.frame.QualificationTypes <- function(xml.parsed) {
    out <- xpathApply(xml.parsed, "//QualificationType", function(x){
        children <- xmlChildren(x)
        return(list(
            QualificationTypeId = xmlValue(children$QualificationTypeId),
            CreationTime = xmlValue(children$CreationTime),
            Name = xmlValue(children$Name),
            Description = xmlValue(children$Description),
            Keywords = xmlValue(children$Keywords),
            QualificationTypeStatus = xmlValue(children$QualificationTypeStatus),
            AutoGranted = xmlValue(children$AutoGranted),
            AutoGrantedValue = xmlValue(children$AutoGrantedValue),
            IsRequestable = xmlValue(children$IsRequestable),
            RetryDelayInSeconds = xmlValue(children$RetryDelayInSeconds),
            TestDurationInSeconds = xmlValue(children$TestDurationInSeconds),
            Test = xmlValue(children$Test),
            AnswerKey = xmlValue(children$AnswerKey)
        ))
    })
    return(do.call(rbind.data.frame,out))
}

as.data.frame.QualificationRequests <- function(xml.parsed){
    out <- xpathApply(xml.parsed, "//QualificationRequest", function(x){
        children <- xmlChildren(x)
        return(list(
            QualificationRequestId = xmlValue(children$QualificationRequestId),
            QualificationTypeId = xmlValue(children$QualificationTypeId),
            SubjectId = xmlValue(children$SubjectId),
            SubmitTime = xmlValue(children$SubmitTime),
            Answer = xmlValue(children$Answer)
        ))
    })
    if(!is.null(out))
        return(list(QualificationRequests = out))
    else
        return(list(QualificationRequests = NULL))
}

as.data.frame.Qualifications <- function(xml.parsed) {
    quals.xml <- xpathApply(xml.parsed, "//Qualification")
    if(length(quals.xml) > 0) {
        quals <- setNames(data.frame(matrix(nrow = length(quals.xml), ncol = 5)),
                    c("QualificationTypeId", "WorkerId", "GrantTime", "Value", "Status"))
        for(i in 1:length(quals.xml)) {
            if("IntegerValue" %in% names(xmlChildren(quals.xml[[1]]))) 
                value.type <- "IntegerValue"
            if("LocaleValue" %in% names(xmlChildren(quals.xml[[1]]))) 
                value.type <- "LocaleValue"
            qual <- xpathApply(xml.parsed,
                paste("//Qualification[", i, "]/QualificationTypeId", sep = ""))
            if(length(qual) == 1) 
                quals[i, 1] <- xmlValue(qual[[1]])
            subj <- xpathApply(xml.parsed,
                paste("//Qualification[", i, "]/SubjectId", sep = ""))
            if(length(subj) == 1) 
                quals[i, 2] <- xmlValue(subj[[1]])
            time <- xpathApply(xml.parsed,
                paste("//Qualification[", i, "]/GrantTime", sep = ""))
            if(length(time) == 1) 
                quals[i, 3] <- xmlValue(time[[1]])
            valu <- xpathApply(xml.parsed,
                paste("//Qualification[", i, "]/", value.type, sep = ""))
            if(length(valu) == 1) 
                quals[i, 4] <- xmlValue(valu[[1]])
            stat <- xpathApply(xml.parsed,
                paste("//Qualification[", i, "]/Status", sep = ""))
            if(length(stat) == 1) 
                quals[i, 5] <- xmlValue(stat[[1]])
        }
        return(Qualifications = quals)
    }
    else
        return(list(Qualifications = NULL))
}


# QUESTION/ANSWER STRUCTURES

as.data.frame.QuestionForm <- function(xml.parsed) {
    qform <- xmlChildren(xmlChildren(xml.parsed)$QuestionForm)
    n <- names(qform)
    out <- mapply(function(x, name){
        if(name=='Question'){
            list(Element = 'Question',
                 QuestionIdentifier = xmlValue(xmlChildren(x)$QuestionIdentifier),
                 DisplayName = xmlValue(xmlChildren(x)$DisplayName),
                 IsRequired = xmlValue(xmlChildren(x)$IsRequired),
                 QuestionContent = xmlValue(xmlChildren(x)$QuestionContent),
                 AnswerSpecification = xmlValue(xmlChildren(x)$AnswerSpecification) )
        } else if(name=='Overview'){
            # this doesn't handle multiple elements well
            list(Element = 'Overview',
                 Title = xmlValue(xmlChildren(x)$Title),
                 Text = xmlValue(xmlChildren(x)$Text),
                 List = sapply(xmlChildren(x)$Text, xmlValue),
                 Binary = xmlToList(xmlChildren(x)$Binary),
                 Application = xmlToList(xmlChildren(x)$Application),
                 EmbeddedBinary = xmlToList(xmlChildren(x)$EmbeddedBinary),
                 FormattedContent = xmlChildren(x)$FormattedContent )
        }
    }, qform, n)
    return(do.call('rbind',out))
}

as.data.frame.HTMLQuestion <- function(xml.parsed) {
    removeXMLNamespaces(xml.parsed, all = TRUE)
    if(length(xmlChildren(xml.parsed)) > 0) {
        html.content <- xmlValue(xmlChildren(xml.parsed)$HTMLContent)
        frame.height <- xmlValue(xmlChildren(xml.parsed)$FrameHeight)
        return(list(html.content = html.content, frame.height = frame.height))
    }
    else
        return(list(html.content = NULL, frame.height = NULL))
}

as.data.frame.ExternalQuestion <- function(xml.parsed) {
    removeXMLNamespaces(xml.parsed, all = TRUE)
    if(length(xmlChildren(xml.parsed)) > 0) {
        external.url <- xmlValue(xmlChildren(xml.parsed)$ExternalURL)
        frame.height <- xmlValue(xmlChildren(xml.parsed)$FrameHeight)
        return(list(external.url = external.url, frame.height = frame.height))
    }
    else
        return(list(external.url = NULL, frame.height = NULL))
}

as.data.frame.AnswerKey <- function(xml.parsed) {
    nodes <- xmlChildren(xmlChildren(xml.parsed)$AnswerKey)
    # need to change this to an xpath expression:
    answerkey <- data.frame(matrix(nrow = length(strsplit(toString(xml.parsed),'/AnswerOption')[[1]])-1,
                                   ncol = 3))
    names(answerkey) <- c("QuestionIdentifier", "SelectionIdentifier", "AnswerScore")
    k <- 1
    for(i in 1:length(nodes[names(nodes) == "Question"])) {
        question <- xmlChildren(nodes[names(nodes) == "Question"][[i]])
        qid <- xmlValue(question$QuestionIdentifier)
        answeroptions <- question[names(question) == "AnswerOption"]
        for(j in 1:length(answeroptions)) {
            answerkey$QuestionIdentifier[k] <- qid
            answerkey$SelectionIdentifier[k] <- xmlValue(xmlChildren(answeroptions[[j]])$SelectionIdentifier)
            answerkey$AnswerScore[k] <- xmlValue(xmlChildren(answeroptions[[j]])$AnswerScore)
            k <- k + 1
        }
    }
    if(!is.null(nodes$QualificationValueMapping)) {
        map <- xmlChildren(nodes$QualificationValueMapping)
        mapping <- list()
        if("PercentageMapping" %in% names(map)) {
            mapping$Type <- "PercentageMapping"
            mapping$MaximumSummedScore <- xmlValue(xmlChildren(map$PercentageMapping)$MaximumSummedScore)
        }
        else if("ScaleMapping" %in% names(map)) {
            mapping$Type <- "ScaleMapping"
            mapping$SummedScoreMultiplier <- xmlValue(xmlChildren(map$PercentageMapping)$SummedScoreMultiplier)
        }
        else if("RangeMapping" %in% names(map)) {
            mapping$Type <- "RangeMapping"
            ranges.xml <- xmlChildren(map$RangeMapping)
            scoreranges <- ranges.xml[names(ranges.xml) == "SummedScoreRange"]
            mapping$Ranges <- data.frame(matrix(nrow=length(scoreranges), ncol=3))
            names(mapping$Ranges) <- c("InclusiveLowerBound", 
                "InclusiveUpperBound", "QualificationValue")
            for(i in 1:length(scoreranges)) {
                mapping$Ranges[i, ] <- c(xmlValue(xmlChildren(scoreranges[[i]])$InclusiveLowerBound), 
                  xmlValue(xmlChildren(scoreranges[[i]])$InclusiveUpperBound), 
                  xmlValue(xmlChildren(scoreranges[[i]])$QualificationValue))
            }
            mapping$OutOfRangeQualificationValue <- xmlValue(ranges.xml$OutOfRangeQualificationValue)
        }
        return(list(Questions = answerkey, Scoring = mapping))
    }
    else
        return(list(Questions = answerkey))
}

as.data.frame.QuestionFormAnswers <- function(xml.parsed) {
    answers <- xpathApply(xml.parsed, "//Answer")
    # estimate length of dataframe:
    total <- length(answers)
    extractQuestionFormAnswersElement <- function(i) {
        z <- xmlChildren(xmlParse(xmlValue(i)))$QuestionFormAnswers
        removeXMLNamespaces(z, all = TRUE)
        return(z)
    }
    z <- extractQuestionFormAnswersElement(answers[[1]])
    questions <- xmlChildren(z)
    iterations <- total * length(questions)
    # create dataframe
    values <- as.data.frame(matrix(nrow = iterations, ncol = 10))
    names(values) <- c("AssignmentId", "WorkerId", "HITId", "QuestionIdentifier", 
                       "FreeText", "SelectionIdentifier", "OtherSelectionField", 
                       "UploadedFileKey", "UploadedFileSizeInBytes", "Combined.Answers")
    convertxml <- function(node){
        questions <- xmlChildren(extractQuestionFormAnswersElement(node))
        out <- as.data.frame(matrix(nrow = length(questions), ncol = 10))
        names(out) <- names(values)
        out$AssignmentId <- xmlValue(xpathApply(node, "../AssignmentId")[[1]])
        out$WorkerId <- xmlValue(xpathApply(node, "../WorkerId")[[1]])
        out$HITId <- xmlValue(xpathApply(node, "../HITId")[[1]])
        for(z in 1:length(questions)){
            if(length(xmlChildren(questions[[z]])$QuestionIdentifier) == 1) 
                out$QuestionIdentifier[z] <- xmlValue(xmlChildren(questions[[z]])$QuestionIdentifier)
            if(length(xmlChildren(questions[[z]])$FreeText) == 1) {
                out$FreeText[z] <- xmlValue(xmlChildren(questions[[z]])$FreeText)
                out$Combined.Answers[z] <- xmlValue(xmlChildren(questions[[z]])$FreeText)
            }
            else if(length(xmlChildren(questions[[z]])$UploadedFileKey) == 1) {
                out$UploadedFileKey[z] <- xmlValue(xmlChildren(questions[[z]])$UploadedFileKey)
                out$UploadedFileSizeInBytes[z] <- xmlValue(xmlChildren(questions[[z]])$UploadedFileSizeInBytes)
                out$Combined.Answers[z] <- paste(out$UploadedFileKey[z], 
                    out$UploadedFileSizeInBytes[z], sep = ":")
            }
            else if (length(xmlChildren(questions[[z]])$SelectionIdentifier) == 1) {
                out$SelectionIdentifier[z] <- xmlValue(xmlChildren(questions[[z]])$SelectionIdentifier)
                out$Combined.Answers[z] <- xmlValue(xmlChildren(questions[[z]])$SelectionIdentifier)
                if(length(xmlChildren(questions[[1]])$OtherSelectionField) == 1) {
                    multiple <- paste(out$SelectionIdentifier[z], 
                                xmlValue(xmlChildren(questions[[z]])$OtherSelectionField), 
                                sep = ";")
                    out$Combined.Answers[z] <- multiple
                    rm(multiple)
                }
            }
            else if(length(xmlChildren(questions[[z]])$SelectionIdentifier) > 1) {
                multiple <- ""
                for(j in 1:length(xmlChildren(questions[[z]])$SelectionIdentifier)) {
                    multiple <- paste(multiple,
                                xmlValue(xmlChildren(xmlChildren(questions[[z]])[j]$QuestionIdentifier)$text),
                                sep = ";")
                }
                if(length(xmlChildren(questions[[z]])$OtherSelectionField) == 1) 
                    multiple <- paste(multiple,
                                xmlValue(xmlChildren(questions[[z]])$OtherSelectionField), 
                                sep = ";")
                out$SelectionIdentifier[z] <- multiple
                out$Combined.Answers[z] <- multiple
                rm(multiple)
            }
            else if(length(xmlChildren(questions[[z]])$OtherSelectionField) == 1) {
                out$OtherSelectionField[z] <- xmlValue(xmlChildren(questions[[z]])$OtherSelectionField)
                out$Combined.Answers[z] <- xmlValue(xmlChildren(questions[[z]])$OtherSelectionField)
            }
        }
        return(out)
    }
    values <- do.call(rbind,lapply(answers,FUN=convertxml))
    return(values)
}



# REVIEW RESULTS

as.data.frame.ReviewResults <- function(xml.parsed) {
    hit.xml <- xpathApply(xml.parsed, "//GetReviewResultsForHITResult")
    if(!is.null(hit.xml) && length(hit.xml) >= 1) {
        hit <- xmlValue(xpathApply(xml.parsed, "//HITId")[[1]])
        if(length(xpathApply(xml.parsed, "//AssignmentReviewPolicy")) > 0) 
            assignment.policy <- xmlValue(xpathApply(xml.parsed, 
                "//AssignmentReviewPolicy")[[1]])
        else
            assignment.policy <- NA
        if(length(xpathApply(xml.parsed, "//HITReviewPolicy")) > 0) 
            hit.policy <- xmlValue(xpathApply(xml.parsed, "//HITReviewPolicy")[[1]])
        else
            hit.policy <- NA
        if(!is.na(assignment.policy)) {
            assignment.report <- xmlChildren(xpathApply(xml.parsed, 
                "//AssignmentReviewReport")[[1]])
            if(!is.null(assignment.report) && length(assignment.report) >= 1) {
                AssignmentReviewResult <- setNames(data.frame(matrix(
                    nrow=sum(names(assignment.report) == "ReviewResult"), ncol=7)),
                    c("AssignmentReviewPolicy", "ActionId", "SubjectId",
                    "ObjectType", "QuestionId", "Key", "Value"))
                AssignmentReviewAction <- setNames(data.frame(matrix(
                    nrow = sum(names(assignment.report) == "ReviewAction"), ncol = 9)),
                    c("AssignmentReviewPolicy", "ActionId", "ActionName", "ObjectId",
                    "ObjectType", "Status", "CompleteTime", "Result", "ErrorCode"))
                r <- 1
                a <- 1
                for(i in 1:length(assignment.report)) {
                  if(xmlName(assignment.report[[i]]) == "ReviewResult") {
                    AssignmentReviewResult$AssignmentReviewPolicy[r] <- assignment.policy
                    AssignmentReviewResult$ActionId[r] <- xmlValue(xmlChildren(assignment.report[[i]])$ActionId)
                    AssignmentReviewResult$SubjectId[r] <- xmlValue(xmlChildren(assignment.report[[i]])$SubjectId)
                    AssignmentReviewResult$ObjectType[r] <- xmlValue(xmlChildren(assignment.report[[i]])$ObjectType)
                    AssignmentReviewResult$QuestionId[r] <- xmlValue(xmlChildren(assignment.report[[i]])$QuestionId)
                    AssignmentReviewResult$Key[r] <- xmlValue(xmlChildren(assignment.report[[i]])$Key)
                    AssignmentReviewResult$Value[r] <- xmlValue(xmlChildren(assignment.report[[i]])$Value)
                    r <- r + 1
                  }
                  else {
                    AssignmentReviewAction$AssignmentReviewPolicy[a] <- assignment.policy
                    AssignmentReviewAction$ActionId[a] <- xmlValue(xmlChildren(assignment.report[[i]])$ActionId)
                    AssignmentReviewAction$ActionName[a] <- xmlValue(xmlChildren(assignment.report[[i]])$ActionName)
                    AssignmentReviewAction$ObjectId[a] <- xmlValue(xmlChildren(assignment.report[[i]])$ObjectId)
                    AssignmentReviewAction$ObjectType[a] <- xmlValue(xmlChildren(assignment.report[[i]])$ObjectType)
                    AssignmentReviewAction$CompleteTime[a] <- xmlValue(xmlChildren(assignment.report[[i]])$CompleteTime)
                    AssignmentReviewAction$Status[a] <- xmlValue(xmlChildren(assignment.report[[i]])$Status)
                    AssignmentReviewAction$Result[a] <- xmlValue(xmlChildren(assignment.report[[i]])$Result)
                    AssignmentReviewAction$ErrorCode[a] <- xmlValue(xmlChildren(assignment.report[[i]])$ErrorCode)
                    a <- a + 1
                  }
                }
            }
        }
        if(!is.na(hit.policy)) {
            hit.report <- xmlChildren(xpathApply(xml.parsed, 
                "//HITReviewReport")[[1]])
            if(!is.null(hit.report) && length(hit.report) >= 1) {
                HITReviewResult <- setNames(data.frame(matrix(
                    nrow = sum(names(hit.report) == "ReviewResult"), ncol = 7)),
                    c("HITReviewPolicy", "ActionId", "SubjectId", "ObjectType",
                    "QuestionId", "Key", "Value"))
                HITReviewAction <- setNames(data.frame(matrix(
                    nrow = sum(names(hit.report) == "ReviewAction"), ncol = 9)),
                    c("HITReviewPolicy", "ActionId", "ActionName", "ObjectId",
                    "ObjectType", "Status", "CompleteTime", "Result", "ErrorCode"))
                r <- 1
                a <- 1
                for(i in 1:length(hit.report)) {
                  if(xmlName(hit.report[[i]]) == "ReviewResult") {
                    HITReviewResult$HITReviewPolicy[r] <- hit.policy
                    HITReviewResult$ActionId[r] <- xmlValue(xmlChildren(hit.report[[i]])$ActionId)
                    HITReviewResult$SubjectId[r] <- xmlValue(xmlChildren(hit.report[[i]])$SubjectId)
                    HITReviewResult$ObjectType[r] <- xmlValue(xmlChildren(hit.report[[i]])$ObjectType)
                    HITReviewResult$QuestionId[r] <- xmlValue(xmlChildren(hit.report[[i]])$QuestionId)
                    HITReviewResult$Key[r] <- xmlValue(xmlChildren(hit.report[[i]])$Key)
                    HITReviewResult$Value[r] <- xmlValue(xmlChildren(hit.report[[i]])$Value)
                    r <- r + 1
                  }
                  else {
                    HITReviewAction$HITReviewPolicy[a] <- hit.policy
                    HITReviewAction$ActionId[a] <- xmlValue(xmlChildren(hit.report[[i]])$ActionId)
                    HITReviewAction$ActionName[a] <- xmlValue(xmlChildren(hit.report[[i]])$ActionName)
                    HITReviewAction$ObjectId[a] <- xmlValue(xmlChildren(hit.report[[i]])$ObjectId)
                    HITReviewAction$ObjectType[a] <- xmlValue(xmlChildren(hit.report[[i]])$ObjectType)
                    HITReviewAction$CompleteTime[a] <- xmlValue(xmlChildren(hit.report[[i]])$CompleteTime)
                    HITReviewAction$Status[a] <- xmlValue(xmlChildren(hit.report[[i]])$Status)
                    HITReviewAction$Result[a] <- xmlValue(xmlChildren(hit.report[[i]])$Result)
                    HITReviewAction$ErrorCode[a] <- xmlValue(xmlChildren(hit.report[[i]])$ErrorCode)
                    a <- a + 1
                  }
                }
            }
        }
        if(is.na(hit.policy) & is.na(assignment.policy)) 
            return(NULL)
        else {
            return.list <- list(AssignmentReviewResult = AssignmentReviewResult, 
                AssignmentReviewAction = AssignmentReviewAction, 
                HITReviewResult = HITReviewResult, HITReviewAction = HITReviewAction)
            return(return.list)
        }
    }
    else
        return(list(AssignmentReviewResult = NULL, AssignmentReviewAction = NULL, 
                HITReviewResult = NULL, HITReviewAction = NULL))
}


# MISC STRUCTURES

as.data.frame.BonusPayments <- function(xml.parsed){
    out <- xpathApply(xml.parsed, "//BonusPayment", function(x){
        children <- xmlChildren(x)
        bonus <- xmlChildren(children$BonusAmount)
        return(list(
            AssignmentId = xmlValue(children$AssignmentId),
            WorkerId = xmlValue(children$WorkerId),
            Amount = xmlValue(bonus$Amount),
            CurrencyCode = xmlValue(bonus$CurrencyCode),
            FormattedPrice = xmlValue(bonus$FormattedPrice),
            Reason = xmlValue(children$Reason),
            GrantTime = xmlValue(children$GrantTime)
        ))
    })
    return(do.call(rbind.data.frame,out))
}

as.data.frame.WorkerBlock <- function(xml.parsed) {
    out <- xpathApply(xml.parsed, "//WorkerBlock", function(x){
        children <- xmlChildren(x)
        return(list(
            WorkerId <- xmlValue(children$WorkerId),
            Reason = xmlValue(children$Reason)
        ))
    })
    return(do.call(rbind.data.frame,out))
}
