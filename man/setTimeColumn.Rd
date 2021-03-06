% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/complexTypes.R
\name{setTimeColumn}
\alias{setTimeColumn}
\title{Sugar to trim a list column by a number
Sugar to trim a column by another column variable
setTimeColumn}
\usage{
setTimeColumn(data, timeCol)
}
\arguments{
\item{data:}{the dataframe / data.table to be modified.}

\item{timeCol:}{The column name in \code{data} to be renamed.}
}
\description{
Rename a requested column to "SB_times_col". When the exported data is read by the SparkBeyond engine, all other columns that contain lists that are of the same size as of the list in "SB_times_col" will be converted into time series data structures.
}

