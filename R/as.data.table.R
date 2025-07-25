as.data.table = function(x, keep.rownames=FALSE, ...)
# cannot add new args before dots otherwise revdeps which implement their methods will start to warn; e.g. riskRegression in #3581
{
  if (is.null(x))
    return(null.data.table())
  UseMethod("as.data.table")
}

as.data.table.default = function(x, ...){
  as.data.table(as.data.frame(x, ...), ...) # we cannot assume as.data.frame will do copy, thus setDT changed to as.data.table #3230
}

as.data.table.factor = as.data.table.ordered =
as.data.table.integer = as.data.table.numeric =
as.data.table.logical = as.data.table.character =
as.data.table.Date = as.data.table.ITime = function(x, keep.rownames=FALSE, key=NULL, ...) {
  if (is.matrix(x)) {
    return(as.data.table.matrix(x, ...))
  }
  tt = deparse(substitute(x))[1L]
  nm = names(x)
  # FR #2356 - transfer names of named vector as "rn" column if required
  if (!identical(keep.rownames, FALSE) && !is.null(nm))
    x = list(nm, unname(x))
  else x = list(x)
  if (tt == make.names(tt)) {
    # can specify col name to keep.rownames, #575
    nm = if (length(x) == 2L) if (is.character(keep.rownames)) keep.rownames[1L] else "rn"
    setattr(x, 'names', c(nm, tt))
  }
  as.data.table.list(x, FALSE, key)
}

# as.data.table.table - FR #361
as.data.table.table = function(x, keep.rownames=FALSE, key=NULL, ...) {
  # prevent #4179 & just cut out here
  if (any(dim(x) == 0L)) return(null.data.table())
  # Fix for bug #43 - order of columns are different when doing as.data.table(with(DT, table(x, y)))
  val = frev(dimnames(provideDimnames(x)))
  if (is.null(names(val)) || !any(nzchar(names(val))))
    setattr(val, 'names', paste0("V", frev(seq_along(val))))
  ans = data.table(do.call(CJ, c(val, sorted=FALSE)), N = as.vector(x), key=key)
  setcolorder(ans, c(frev(head(names(ans), -1L)), "N"))
  ans
}

as.data.table.matrix = function(x, keep.rownames=FALSE, key=NULL, ...) {
  if (!identical(keep.rownames, FALSE)) {
    # can specify col name to keep.rownames, #575
    ans = data.table(rn=rownames(x), x, keep.rownames=FALSE)
    # auto-inferred name 'x' is not back-compatible & inconsistent, #7145
    if (ncol(x) == 1L && is.null(colnames(x)))
      setnames(ans, 'x', 'V1', skip_absent=TRUE)
    if (is.character(keep.rownames))
      setnames(ans, 'rn', keep.rownames[1L])
    return(ans)
  }
  d = dim(x)
  ncols = d[2L]
  ic = seq_len(ncols)
  if (!ncols) return(null.data.table())

  value = vector("list", ncols)
  if (mode(x) == "character") {
    # fix for #745 - A long overdue SO post: http://stackoverflow.com/questions/17691050/data-table-still-converts-strings-to-factors
    for (i in ic) value[[i]] = x[, i]                  # <strike>for efficiency.</strike> For consistency - data.table likes and prefers "character"
  }
  else {
    for (i in ic) value[[i]] = as.vector(x[, i])       # to drop any row.names that would otherwise be retained inside every column of the data.table
  }
  col_labels = dimnames(x)[[2L]]
  setDT(value)
  if (length(col_labels) == ncols) {
    if (any(empty <- !nzchar(col_labels)))
      col_labels[empty] = paste0("V", ic[empty])
    setnames(value, col_labels)
  } else {
    setnames(value, paste0("V", ic))
  }
  # setkey now to allow matrix column names as key
  setkeyv(value, key)
  value
}

# as.data.table.array - #1418
as.data.table.array = function(x, keep.rownames=FALSE, key=NULL, sorted=TRUE, value.name="value", na.rm=TRUE, ...) {
  dx = dim(x)
  if (length(dx) <= 2L)
    stopf("as.data.table.array method should only be called for arrays with 3+ dimensions; use the matrix method for 2-dimensional arrays")
  if (!is.character(value.name) || length(value.name)!=1L || is.na(value.name) || !nzchar(value.name))
    stopf("Argument 'value.name' must be scalar character, non-NA and at least one character")
  if (!is.logical(sorted) || length(sorted)!=1L || is.na(sorted))
    stopf("Argument 'sorted' must be scalar logical and non-NA")
  if (!is.logical(na.rm) || length(na.rm)!=1L || is.na(na.rm))
    stopf("Argument 'na.rm' must be scalar logical and non-NA")
  if (!missing(sorted) && !is.null(key))
    stopf("Please provide either 'key' or 'sorted', but not both.")

  dnx = dimnames(x)
  # NULL dimnames will create integer keys, not character as in table method
  val = if (is.null(dnx)) {
    lapply(dx, seq_len)
  } else if (any(nulldnx <- vapply_1b(dnx, is.null))) {
    dnx[nulldnx] = lapply(dx[nulldnx], seq_len) #3636
    dnx
  } else dnx
  setfrev(val)
  if (is.null(names(val)) || !any(nzchar(names(val))))
    setattr(val, 'names', paste0("V", frev(seq_along(val))))
  if (value.name %chin% names(val))
    stopf("Argument 'value.name' should not overlap with column names in result: %s", brackify(frev(names(val))))
  N = NULL
  ans = do.call(CJ, c(val, sorted=FALSE))
  set(ans, j="N", value=as.vector(x))
  if (isTRUE(na.rm))
    ans = ans[!is.na(N)]
  setnames(ans, "N", value.name)
  dims = frev(head(names(ans), -1L))
  setcolorder(ans, c(dims, value.name))
  if (isTRUE(sorted) && is.null(key)) key = dims
  setkeyv(ans, key)
  ans[]
}

as.data.table.list = function(x,
  keep.rownames=FALSE,
  key=NULL,
  check.names=FALSE,
  .named=NULL,  # (internal) whether the argument was named in the data.table() or cbind() call calling this as.data.table.list()
                # e.g. cbind(foo=DF1, bar=DF2) have .named=c(TRUE,TRUE) due to the foo= and bar= and trigger "prefix." for non-vector items
  ...)
{
  n = length(x)
  eachnrow = integer(n)          # vector of lengths of each column. may not be equal if silent repetition is required.
  eachncol = integer(n)
  missing.check.names = missing(check.names)
  origListNames = if (missing(.named)) names(x) else NULL  # as.data.table called directly, not from inside data.table() which provides .named, #3854
  empty_atomic = FALSE

  # Handle keep.rownames for vectors (mimicking data.frame behavior)
  rownames_ = NULL
  check_rownames = !isFALSE(keep.rownames)

  for (i in seq_len(n)) {
    xi = x[[i]]
    if (is.null(xi)) next    # eachncol already initialized to 0 by integer() above
    if (check_rownames && is.null(rownames_)) {
      if (is.null(dim(xi))) {
        if (!is.null(nm <- names(xi))) {
          rownames_ = nm
          x[[i]] = unname(xi)
        }
      } else {
        if (!is.null(nm <- rownames(xi))) {
          rownames_ = nm
        }
      }
    }
    if (!is.null(dim(xi)) && missing.check.names) check.names=TRUE
    if ("POSIXlt" %chin% class(xi)) {
      warningf("POSIXlt column type detected and converted to POSIXct. We do not recommend use of POSIXlt at all because it uses 40 bytes to store one date.")
      xi = x[[i]] = as.POSIXct(xi)
    } else if (is.matrix(xi) || is.data.frame(xi)) {
      if (!is.data.table(xi)) {
        if (is.matrix(xi) && NCOL(xi)==1L && is.null(colnames(xi)) && isFALSE(getOption('datatable.old.matrix.autoname'))) { # 1 column matrix naming #4124
          xi = x[[i]] = c(xi)
        } else {
          xi = x[[i]] = as.data.table(xi, keep.rownames=keep.rownames)  # we will never allow a matrix to be a column; always unpack the columns
        }
      }
      # else avoid dispatching to as.data.table.data.table (which exists and copies)
    } else if (is.table(xi)) {
      xi = x[[i]] = as.data.table.table(xi, keep.rownames=keep.rownames)
    } else if (is.function(xi)) {
      xi = x[[i]] = list(xi)
    }
    eachnrow[i] = NROW(xi)    # for a vector (including list() columns) returns the length
    eachncol[i] = NCOL(xi)    # for a vector returns 1
    if (is.atomic(xi) && length(xi)==0L && !is.null(xi)) {
      empty_atomic = TRUE  # any empty atomic (not empty list()) should result in nrows=0L, #3727
    }
  }
  ncol = sum(eachncol)  # hence removes NULL items silently (no error or warning), #842.
  if (ncol==0L) return(null.data.table())
  nrow = if (empty_atomic) 0L else max(eachnrow)
  ans = vector("list",ncol)  # always return a new VECSXP
  recycle = function(x, nrow) {
    if (length(x)==nrow) {
      return(copy(x))
      # This copy used to be achieved via .Call(CcopyNamedInList,x) at the top of data.table(). It maintains pre-Rv3.1.0
      # behavior, for now. See test 548.2. The copy() calls duplicate() at C level which (importantly) also expands ALTREP objects.
      # TODO: port this as.data.table.list() to C and use MAYBE_REFERENCED(x) || ALTREP(x) to save some copies.
      #       That saving used to be done by CcopyNamedInList but the copies happened again as well, so removing CcopyNamedInList is
      #       not worse than before, and gets us in a better centralized place to port as.data.table.list to C and use MAYBE_REFERENCED
      #       again in future, for #617.
    }
    if (identical(x, list())) vector("list", nrow) else safe_rep_len(x, nrow)   # new objects don't need copy
  }
  vnames = character(ncol)
  k = 1L
  n_null = 0L
  for(i in seq_len(n)) {
    xi = x[[i]]
    if (is.null(xi)) { n_null = n_null+1L; next }
    if (eachnrow[i]>1L && nrow%%eachnrow[i]!=0L)   # in future: eachnrow[i]!=nrow
      warningf("Item %d has %d rows but longest item has %d; recycled with remainder.", i, eachnrow[i], nrow)
    if (is.data.table(xi)) {   # matrix and data.frame were coerced to data.table above
      prefix = if (!isFALSE(.named[i]) && isTRUE(nzchar(names(x)[i], keepNA=TRUE))) paste0(names(x)[i],".") else ""  # test 2058.12
      for (j in seq_along(xi)) {
        ans[[k]] = recycle(xi[[j]], nrow)
        vnames[k] = paste0(prefix, names(xi)[j])
        k = k+1L
      }
    } else {
      nm = names(x)[i]
      vnames[k] = if (length(nm) && !is.na(nm) && nm!="") nm else paste0("V",i-n_null)  # i (not k) tested by 2058.14 to be the same as the past for now
      ans[[k]] = recycle(xi, nrow)
      k = k+1L
    }
  }
  if (any(vnames==".SD")) stopf("A column may not be called .SD. That has special meaning.")
  if (check.names) vnames = make.names(vnames, unique=TRUE)

  # Add rownames column when vector names were found
  if (!is.null(rownames_)) {
    rn_name = if (is.character(keep.rownames)) keep.rownames[1L] else "rn"
    if (!is.na(idx <- chmatch(rn_name, vnames)[1L])) {
      ans = c(list(ans[[idx]]), ans[-idx])
      vnames = c(vnames[idx], vnames[-idx])
    } else {
      ans = c(list(recycle(rownames_, nrow)), ans)
      vnames = c(rn_name, vnames)
    }
  }
  setattr(ans, "names", vnames)
  setDT(ans, key=key) # copy ensured above; also, setDT handles naming
  if (length(origListNames)==length(ans)) setattr(ans, "names", origListNames)  # PR 3854 and tests 2058.15-17
  ans
}

# don't retain classes before "data.frame" while converting
# from it.. like base R does. This'll break test #527 (see
# tests and as.data.table.data.frame) I've commented #527
# for now. This addresses #1078 and #1128
.resetclass = function(x, class) {
  if (length(class)!=1L)
    stopf("class must be length 1") # nocov
  cx = class(x)
  n  = chmatch(class, cx)   # chmatch accepts length(class)>1 but next line requires length(n)==1
  unique( c("data.table", "data.frame", tail(cx, length(cx)-n)) )
}

as.data.table.data.frame = function(x, keep.rownames=FALSE, key=NULL, ...) {
  if (is.data.table(x)) return(as.data.table.data.table(x, key=key)) # S3 is weird, #6739. Also # nocov; this is tested in 2302.{2,3}, not sure why it doesn't show up in coverage.
  if (!identical(class(x), "data.frame")) {
    class_orig = class(x)
    x = as.data.frame(x)
    if (identical(class(x), class_orig)) setattr(x, "class", "data.frame") # cater for cases when as.data.frame can generate a loop #6874
    return(as.data.table.data.frame(x, keep.rownames=keep.rownames, key=key, ...))
  }
  if (!isFALSE(keep.rownames)) {
    # can specify col name to keep.rownames, #575; if it's the same as key,
    #   kludge it to 'rn' since we only apply the new name afterwards, #4468
    if (is.character(keep.rownames) && identical(keep.rownames, key)) key='rn'
    ans = data.table(rn=rownames(x), x, keep.rownames=FALSE, key=key)
    if (is.character(keep.rownames))
      setnames(ans, 'rn', keep.rownames[1L])
    return(ans)
  }
  if (any(cols_with_dims(x))) {
    # a data.frame with a column that is data.frame needs to be expanded; test 2013.4
    # x may be a class with [[ method that behaves differently, so as.list first for default [[, #4526
    return(as.data.table.list(as.list(x), keep.rownames=keep.rownames, key = key,...))
  }
  ans = copy(x)  # TO DO: change this deep copy to be shallow.
  setattr(ans, "row.names", .set_row_names(nrow(x)))

  ## NOTE: This test (#527) is no longer in effect ##
  # for nlme::groupedData which has class c("nfnGroupedData","nfGroupedData","groupedData","data.frame")
  # See test 527.
  ##

  # fix for #1078 and #1128, see .resetclass() for explanation.
  setattr(ans, "class", .resetclass(x, "data.frame"))
  setalloccol(ans)
  setkeyv(ans, key)
  ans
}

as.data.table.data.table = function(x, ..., key=NULL) {
  # as.data.table always returns a copy, automatically takes care of #473
  if (any(cols_with_dims(x))) { # for test 2089.2
    return(as.data.table.list(x, key = key, ...))
  }
  x = copy(x) # #1681
  # fix for #1078 and #1128, see .resetclass() for explanation.
  setattr(x, 'class', .resetclass(x, "data.table"))
  if (!missing(key)) setkeyv(x, key)
  x
}
