MEM <- function(exp_data, transform=FALSE, cofactor=1, choose.markers=FALSE,markers="all",choose.ref=FALSE,zero.ref=FALSE,rename.markers=FALSE,new.marker.names="none",file.is.clust=FALSE,add.fileID=FALSE,IQR.thresh=NULL,output.prescaled.MEM=FALSE,scale.matrix = "linear",scale.factor = 0)
{
    if (file.is.clust == TRUE) {
        file_order <- exp_data}else {file_order <- 0}

    # Check user input
    if(missing(exp_data)){
        warning("Data not found. See documentation for accepted data types",call.=FALSE)
    }
    if(is(exp_data,"character") && missing(file.is.clust) && length(exp_data) > 1){
        warning("There are multiple files. Please specify if each file is cluster using file.is.clust arg",call.=FALSE)
        return(exp_data)
    }
    if(is(exp_data,"character") || is(exp_data,"matrix") || is(exp_data,"data.frame")){
      }else{
        warning("Incorrect data type. See documentation for accepted data types",call.=FALSE)
        return(exp_data)
    }

    #Check to see if there are multiple file types in folder
    if(is(exp_data,"character")){
        all_exts <- lapply(exp_data,file_ext)
        if(isTRUE(all.equal(all_exts,rep(all_exts[1],length(all_exts))))==FALSE){
            warning("Directory contains multiple file types. Remove all files except those to be included in analysis",call. = FALSE)
            return(exp_data)
        }
    }

    # If user has input multiple files, call get.files; else read in data based on ext type
    if(is(exp_data,"character") && length(exp_data) > 1){
        exp_data <- exp_data[ !grepl("output files",exp_data)]

        exp_data <- format.data(exp_data,file.is.clust,add.fileID)

    } else if(is(exp_data,"matrix") || is(exp_data,"data.frame")) {
        exp_data <- as.data.frame(exp_data)

    } else {
        if("fcs" %in% file_ext(exp_data)){
            exp_data <- exprs(read.FCS(exp_data))
        }
        if("csv" %in% file_ext(exp_data)){
            exp_data <- read.table(exp_data,sep=",",header=TRUE)
        }
        if("txt" %in% file_ext(exp_data)){
            exp_data <- read.table(exp_data,sep="\t",header=TRUE)
        }
    }
    # Get markers to include in analysis and extract column names
    marker_names <- as.vector(c(colnames(exp_data)[seq_len(ncol(exp_data)-1)],"cluster"))
    if(choose.markers==TRUE){
        markerList <- choose_markers(exp_data)}else if(choose.markers == FALSE && markers == "all"){
            markerList<-c(seq_len(ncol(exp_data)))}else{sep_vals <- unlist(strsplit(markers,","))
            list_vals <- vector()
            for(i in seq_len(length(sep_vals))){
                val <- sep_vals[i]
                if(length(unlist(strsplit(val,":"))) > 1){
                    new_val <- as.numeric(unlist(strsplit(val,":"))[1]):as.numeric(unlist(strsplit(val,":"))[2])
                }else{
                    new_val<-as.numeric(sep_vals[i])
                }
                list_vals <- c(list_vals,new_val)
            }
            markerList <- c(list_vals,ncol(exp_data))
            }

    exp_data <- as.data.frame(as.data.frame(exp_data)[,c(markerList)])
    marker_names <- colnames(exp_data)

    # Rename markers
    if(rename.markers==TRUE){
        new_marker_names <- rename_markers(exp_data,marker_names)
    }else if(rename.markers==FALSE && new.marker.names=="none"){
        new_marker_names <- marker_names
    }else{
        user_input_names <- new.marker.names
        new_marker_names <- as.character(unlist(strsplit(user_input_names,",")))
        if(length(new_marker_names)!=(length(marker_names)-1)){
            warning("Number of new marker names does not match number of markers.",call.=FALSE,immediate.=TRUE)
            new_marker_names <- rename_markers(exp_data,marker_names)
        }
        # Add cluster column name
        new_marker_names <- c(new_marker_names,"cluster")
    }

    marker_names <- new_marker_names

    #  Initialize variables
    marker_names <- as.vector(marker_names)
    num_markers <- ncol(exp_data)
    colnames(exp_data) <- marker_names
    num_cells <- nrow(exp_data)
    num_pops <- length(unique(exp_data$cluster))
    pop_names <- unique(exp_data$cluster)

    MAGpop <- matrix(nrow=num_pops,ncol=num_markers)
    MAGref <- matrix(nrow=num_pops,ncol=num_markers)
    IQRpop <- matrix(nrow=num_pops,ncol=num_markers)
    IQRref <- matrix(nrow=num_pops,ncol=num_markers)

    # Transform values if specified
    if(transform==TRUE){
        exp_data <- as.data.frame(cbind(asinh(exp_data[,seq_len(num_markers-1)]/cofactor),exp_data[,num_markers]))
        colnames(exp_data) <- marker_names
    }

    # Get population medians and IQRs
    for(i in seq_len(num_pops)){
        pop <- pop_names[i]
        MAGpop[i,] <- abs(apply(subset(exp_data,cluster==pop),2,FUN=median,na.rm=TRUE))
        IQRpop[i,] <- apply(subset(exp_data,cluster==pop),2,FUN=IQR,na.rm=TRUE)
        idx <- which(exp_data[,"cluster"] == pop)
    }

    # Get reference population medians and IQRs
    if(choose.ref==TRUE){
        altRef_vals <- choose_ref(exp_data,pop_names,num_pops,num_markers)
        MAGref <- altRef_vals[[1]]
        IQRref <- altRef_vals[[2]]
        zero.ref == FALSE
    }else if(zero.ref==TRUE){
        zeroRef_vals <- zero_ref(exp_data,num_pops,num_markers)
        MAGref <- zeroRef_vals[[1]]
        IQRref <- zeroRef_vals[[2]]
    }else{
        for(i in seq_len(num_pops)){
            pop <- pop_names[i]
            MAGref[i,] <- abs(apply(subset(exp_data,cluster!=pop),2,FUN=median,na.rm=TRUE))
            IQRref[i,] <- apply(subset(exp_data,cluster!=pop),2,FUN=IQR,na.rm=TRUE)
            idx <- which(exp_data[,"cluster"] != pop)
        }
    }

    # Set and apply IQR threshold
    if(is.null(IQR.thresh)){
        IQR.thresh<-0.5
    }

    if(num_pops<4){
        IQR.thresh<-0.5
    }

    if(IQR.thresh=="auto"){
        IQR.thresh<-IQR_thresh(MAGpop,MAGref,IQRpop,IQRref,num_markers)
    }

    for(i in seq_len((num_markers-1))){
        IQRpop[,i] <- pmax(IQRpop[,i],IQR.thresh)
        IQRref[,i] <- pmax(IQRref[,i],IQR.thresh)
    }

    IQRcomp <- (IQRref/IQRpop)-1
    # If IQRpop > IQRref, set IQRcomp to 0 (IQRcomp will only be less than 0 if IQRpop > IQRref)
    IQRcomp[IQRcomp<0] <- 0


    if(zero.ref == TRUE){
        IQRcomp[(MAGpop<1.44)] <- 0}

    # Calculate MEM scores
    MAG_diff <- MAGpop-MAGref
    MEM_matrix <- abs(MAGpop-MAGref)+IQRcomp

    # If MAGpop < MAGref or MAGpop = MAGref, negate MEM score (i.e. if MAGdiff = 0)
    MEM_matrix[!(MAG_diff>=0)] <- (-MEM_matrix[!(MAG_diff>=0)])

    if(zero.ref == TRUE){
        MEM_matrix[MEM_matrix<0] <- 0}

    # Put MEM values on -10 to +10 scale
    prescaled_MEM_matrix <- MEM_matrix

    if(scale.matrix == "linear"){
        scale_max <- max(abs(MEM_matrix[,c(seq_len(ncol(MEM_matrix)-1))]))
        MEM_matrix <- cbind((MEM_matrix[,c(seq_len(ncol(MEM_matrix)-1))]/scale_max)*10,MEM_matrix[,ncol(MEM_matrix)])
    }else if(scale.matrix == "log"){
        scaled_matrix <- log(MEM_matrix,base = exp(scale.factor))
        scale_max <- max(abs(scaled_matrix[,c(seq_len(ncol(scaled_matrix)-1))]))
        scale_min <- min(abs(scaled_matrix[,c(seq_len(ncol(scaled_matrix)-1))]))
        MEM_matrix <- cbind(((scaled_matrix[,c(seq_len(ncol(scaled_matrix)-1))]-scale_min)/scale_max)*10,scaled_matrix[,ncol(scaled_matrix)])
    }else if(scale.matrix == "arcsinh"){
        scaled_matrix <- asinh(MEM_matrix/scale.factor)
        scale_max <- max(abs(scaled_matrix[,c(seq_len(ncol(scaled_matrix)-1))]))
        scale_min <- min(abs(scaled_matrix[,c(seq_len(ncol(scaled_matrix)-1))]))
        MEM_matrix <- cbind(((scaled_matrix[,c(seq_len(ncol(scaled_matrix)-1))]-scale_min)/scale_max)*10,scaled_matrix[,ncol(scaled_matrix)])}

    #Rename rows and columns of all matrices
    rename_table <- function(x){
        colnames(x) <- marker_names[seq_len((length(marker_names)-1))]
        rownames(x) <- pop_names
        return(x)
    }

    # Apply rename_table function across matrices
    object_list_labeled <- lapply(list(MAGpop[,seq_len(c(length(marker_names)-1))],MAGref[,seq_len(c(length(marker_names)-1))],IQRpop[,seq_len(c(length(marker_names)-1))],IQRref[,seq_len(c(length(marker_names)-1))],MEM_matrix[,seq_len(c(length(marker_names))-1)]),rename_table)
    object_list_labeled[[6]] <- file_order

    #     # List all matrices for export
    all_values <- list("MAGpop" = object_list_labeled[1],"MAGref"=object_list_labeled[2],"IQRpop"=object_list_labeled[3],"IQRref"=object_list_labeled[4],"MEM_matrix"=object_list_labeled[5],"File Order" = object_list_labeled[6])

    if(output.prescaled.MEM == TRUE){
        colnames(prescaled_MEM_matrix) <- marker_names
        dir.create(file.path(getwd(), "output files"), showWarnings = FALSE)
        write.table(as.matrix(prescaled_MEM_matrix[,c(seq_len(ncol(prescaled_MEM_matrix)-1))]),paste("./output files/",strftime(Sys.time(),"%Y-%m-%d_%H%M%S")," Pre-scaled MEM matrix.txt",sep=""),sep="\t",row.names=TRUE)
    }

    return(all_values)

}

