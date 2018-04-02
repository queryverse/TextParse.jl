using DataStructures

export csvread
const current_record = Ref{Any}()
const debug = Ref{Bool}(false)

const StringLike = Union{AbstractString, StrRange}

optionsiter(opts::Associative) = opts
optionsiter(opts::AbstractVector) = enumerate(opts)

getbyheader(opts, header, i::Int) = opts[i]
getbyheader(opts, header, i::Symbol) = getbyheader(opts, header, string(i))
function getbyheader(opts, header, i::AbstractString)
    if !(i in header)
        throw(ArgumentError("Unknown column $i"))
    end
    getbyheader(opts, header, findfirst(header, i))
end

function optionsiter(opts::Associative, header)
    isempty(header) && return opts
    iter = Dict{Int,Any}()
    for (k, v) in opts
        i = try
            getbyheader(1:length(header), header, k)
        catch err
            if isa(err, ArgumentError)
                continue
            end
        end
        iter[i] = v
    end
    iter
end

optionsiter(opts::AbstractVector, header) = optionsiter(opts)

tofield(f::AbstractField, opts) = f
tofield(f::AbstractToken, opts) = Field(f)
tofield(f::StringToken, opts) = Field(Quoted(f))
tofield(f::Type, opts) = tofield(fromtype(f), opts)
tofield(f::Type{String}, opts) = tofield(fromtype(StrRange), opts)
tofield(f::DateFormat, opts) = tofield(DateTimeToken(DateTime, f), opts)

"""
    csvread(file::Union{String,IO}, delim=','; <arguments>...)

Read CSV from `file`. Returns a tuple of 2 elements:
1. A tuple of columns each either a `Vector`, `DataValueArray` or `PooledArray`
2. column names if `header_exists=true`, empty array otherwise

# Arguments:

- `file`: either an IO object or file name string
- `delim`: the delimiter character
- `spacedelim`: (Bool) parse space-delimited files. `delim` has no effect if true.
- `quotechar`: character used to quote strings, defaults to `"`
- `escapechar`: character used to escape quotechar in strings. (could be the same as quotechar)
- `pooledstrings`: whether to try and create PooledArray of strings
- `nrows`: number of rows in the file. Defaults to `0` in which case we try to estimate this.
- `skiplines_begin`: skips specified number of lines at the beginning of the file
- `header_exists`: boolean specifying whether CSV file contains a header
- `nastrings`: strings that are to be considered NA. Defaults to `TextParse.NA_STRINGS`
- `colnames`: manually specified column names. Could be a vector or a dictionary from Int index (the column) to String column name.
- `colparsers`: Parsers to use for specified columns. This can be a vector or a dictionary from column name / column index (Int) to a "parser". The simplest parser is a type such as Int, Float64. It can also be a `dateformat"..."`, see [CustomParser](@ref) if you want to plug in custom parsing behavior
- `type_detect_rows`: number of rows to use to infer the initial `colparsers` defaults to 20.
"""
csvread(file::String, delim=','; kwargs...) = _csvread_f(file, delim; kwargs...)[1:2]

function csvread(file::IOStream, delim=','; kwargs...)
    mmap_data = Mmap.mmap(file)
    _csvread(String(mmap_data), delim; kwargs...)
end

function csvread(buffer::IO, delim=','; kwargs...)
    mmap_data = read(buffer)
    _csvread(String(mmap_data), delim; kwargs...)
end

function _csvread(str::AbstractString, delim=','; kwargs...)
    _csvread_internal(str, delim; kwargs...)[1:2]
end

function _csvread_f(file::AbstractString, delim=','; kwargs...)
    # Try to detect file extension for compressed files
    ext = last(split(file, '.'))

    if ext == "gz" # Gzipped
        return open(GzipDecompressorStream, file, "r") do io
            data = read(io)
            _csvread_internal(String(data), delim; filename=file, kwargs...)
        end
    else # Otherwise just try to read the file
        return open(file, "r") do io
            data = Mmap.mmap(io)
            _csvread_internal(String(data), delim; filename=file, kwargs...)
        end
    end
end

const ColsPool = OrderedDict{Union{Int, String}, AbstractVector}

function csvread(files::AbstractVector{T},
                 delim=','; kwargs...) where {T<:AbstractString}
    @assert !isempty(files)
    colspool = ColsPool()
    cols, headers, parsers, nrows = try
        _csvread_f(files[1], delim;
                   noresize=true,
                   colspool=colspool,
                   kwargs...)
    catch err
        println(STDERR, "Error parsing $(files[1])")
        rethrow(err)
    end

    count = Int[nrows]
    prev = nrows
    for f in files[2:end]
        if !isempty(cols) && length(cols[1]) == nrows
            n = ceil(Int, nrows * sqrt(2))
            resizecols(colspool, n)
        end
        cols, headers, parsers, nrows = try
            _csvread_f(f, delim; rowno=nrows+1, colspool=colspool,
                       prevheaders=headers, noresize=true, prev_parsers=parsers, kwargs...)
        catch err
            println(STDERR, "Error parsing $(f)")
            rethrow(err)
        end
        push!(count, nrows - prev)
        prev = nrows
    end

    resizecols(colspool, nrows)
    (values(colspool)...), collect(keys(colspool)), count
end

# read CSV in a string
function _csvread_internal(str::AbstractString, delim=',';
                 spacedelim=false,
                 quotechar='"',
                 escapechar='"',
                 pooledstrings=true,
                 noresize=false,
                 rowno::Int=1,
                 prevheaders=nothing,
                 skiplines_begin=0,
                 samecols=nothing,
                 header_exists=true,
                 nastrings=NA_STRINGS,
                 colnames=String[],
                 #ignore_empty_rows=true,
                 colspool = ColsPool(),
                 nrows = !isempty(colspool) ?
                     length(first(colspool)[2]) : 0,
                 prev_parsers = nothing,
                 colparsers=[],
                 filename=nothing,
                 type_detect_rows=20)

    opts = LocalOpts(delim, spacedelim, quotechar, escapechar, false, false)
    len = endof(str)
    pos = start(str)
    rowlength_sum = 0   # sum of lengths of rows, for estimating nrows
    lineno = 0

    c, i = next(str, pos)
    if c == '\ufeff'
        pos = i
    end

    pos, lines = eatnewlines(str, pos)
    lineno += lines
    while lineno < skiplines_begin
        pos = getlineend(str, pos)
        _, pos = next(str, pos)
        pos, lines = eatnewlines(str, pos)
        lineno += lines
    end
    if header_exists
        merged_colnames, pos = readcolnames(str, opts, pos, colnames)
        lineno += 1
    else
        merged_colnames = colnames
    end
    merged_colnames = map(string, merged_colnames)

    if !issorted(nastrings)
        nastrings = sort(nastrings)
    end

    pos1 = pos

    if samecols === nothing
        canonnames = merged_colnames
    else
        canonnames = map(merged_colnames) do c
            canonical_name(samecols, c)
        end
    end

    # seed guesses using those from previous file
    guess, pos1 = guesscolparsers(str, canonnames, opts,
                                  pos, type_detect_rows, colparsers,
                                  nastrings, prev_parsers)
    if isempty(canonnames)
        canonnames = Any[1:length(guess);]
    end

    for (i, v) in enumerate(guess)
        c = get(canonnames, i, i)
        # Make column nullable if it's showing up for the
        # first time, but not in the first file
        if !(fieldtype(v) <: StringLike) && prev_parsers !== nothing && !haskey(colspool, c)
            v = isa(v, NAToken) ? v : NAToken(v)
        end
        p = tofield(v, opts)
        guess[i] = p
    end

    # the last field is delimited by line end
    if !isempty(guess)
        guess[end] = swapinner(guess[end], guess[end]; eoldelim = true)
        rec = Record((guess...,))
    else
        parsers = prev_parsers === nothing ? Dict() : copy(prev_parsers)
        rec = Record(())
        return (), String[], parsers, rowno-1
    end

    if isempty(canonnames)
        canonnames = Any[1:length(rec.fields);]
    end

    current_record[] = rec

    if nrows == 0
        # just an estimate, with some margin
        nrows = ceil(Int, pos1/max(1, lineno) * sqrt(2))
    end

    if isempty(colspool)
        # this is the first file, use nrows
        cols = makeoutputvecs(rec, nrows, pooledstrings)
        for (c, h) in zip(cols, canonnames)
            colspool[h] = c
        end
    else
        _cols = map(1:length(rec.fields)) do i
            c = get(canonnames, i, i)
            f = rec.fields[i]
            if haskey(colspool, c)
                if eltype(colspool[c]) == fieldtype(f) || (fieldtype(f) <: StrRange && eltype(colspool[c]) <: AbstractString)
                    return colspool[c]
                else
                    try
                        return colspool[c] = promote_column(colspool[c],
                                                            rowno-1,
                                                            fieldtype(f))
                    catch err
                        error("Could not convert column $c of eltype $(eltype(colspool[c])) to eltype $(fieldtype(f))")
                    end
                end
            else
                return colspool[c] = makeoutputvec(f, nrows, pooledstrings)
            end
        end
        # promote missing columns to nullable
        missingcols = setdiff(collect(keys(colspool)), canonnames)
        for k in missingcols
            if !(eltype(colspool[k]) <: DataValue) && !(eltype(colspool[k]) <: StringLike)
                colspool[k] = promote_column(colspool[k],
                                             rowno-1,
                                             DataValue{eltype(colspool[k])})
            end
        end
        cols = (_cols...)
    end

    if any(c->length(c) != nrows, cols)
        resizecols(colspool, nrows)
    end

    finalrows = rowno
    @label retry
    try
        finalrows = parsefill!(str, opts, rec, nrows, cols, colspool,
                               pos, lineno, rowno, endof(str))
        if !noresize
            resizecols(colspool, finalrows)
        end
    catch err

        if !isa(err, CSVParseError)
            rethrow(err)
        end

        err.filename = filename

        if err.err_code == PARSE_ERROR

            rng = getlineat(str, err.fieldpos)
            f, l = first(rng), last(rng)
            field = rec.fields[err.colno]

            if l !== endof(str) && err.pos >= l && !field.eoldelim
                if fieldtype(field) <: AbstractString || fieldtype(field) <: StrRange
                    # retry assuming newlines can be part of the field
                    wopts = LocalOpts(opts.endchar, opts.spacedelim, opts.quotechar, opts.escapechar, opts.includequotes, true)
                    fieldsvec = Any[rec.fields...]
                    fieldsvec[err.colno] = swapinner(field, WrapLocalOpts(wopts, field.inner))
                    rec = Record((fieldsvec...))
                    pos = first(rng)
                    rowno = err.rowno
                    lineno = err.lineno
                    @goto retry
                end
                println(STDERR, "Expected another field on row $(err.rowno) (line $(err.lineno))")
                err.filename = filename
                rethrow(err)
            end

            # figure out a new token type for this column and the rest
            # it's very likely that a number of columns change type in a single row
            # so we promote all columns after the failed column
            failed_strs = quotedsplit(str[err.fieldpos:l], opts, true)

            if length(failed_strs) != length(cols[err.colno:end])
                fn = err.filename === nothing ? "" : "In $(err.filename) "
                warn("$(fn)line $(err.lineno) has $(length(err.colno) + length(failed_strs) - 1) fields but $(length(cols)) fields are expected. Skipping row.")
                pos = last(rng)+1
                rowno = err.rowno
                lineno = err.lineno+1
                @goto retry
            end
            promoted = map(failed_strs, err.colno:length(cols)) do s, colidx
                col = cols[colidx]
                f = rec.fields[colidx]
                name = get(canonnames, colidx, colidx)
                c = promote_field(s, f, col, err, nastrings)
                colspool[name] = c[2]
                c
            end

            newfields = map(first, promoted)
            newcols = map(last, promoted)

            if field.inner == newfields[1].inner
                println(STDERR, "Could not determine which type to promote column to.")
                rethrow(err)
            end

            fieldsvec = Any[rec.fields...]
            fieldsvec[err.colno:end] = newfields
            typeof(cols)
            colsvec = Any[cols...]
            colsvec[err.colno:end] = newcols

            rec = Record((fieldsvec...))
            cols = (colsvec...)
            rowno = err.rowno
            lineno = err.lineno
            pos = first(rng)
            @goto retry

        elseif err.err_code == POOL_CROWDED

            colsvec = Any[cols...]
            failcol = cols[err.colno]

            if debug[]
                println(STDERR, "Pool too crowded. $(length(failcol.pool)) unique out of $(length(failcol)). Promoting to array of string")
            end

            @assert isa(failcol, PooledArray)
            # promote to a dense array
            newcol = Array(failcol)
            colsvec[err.colno] = newcol
            colspool[canonnames[err.colno]] = newcol

            rng = getlineat(str, err.fieldpos)

            pos = first(rng)
            rowno = err.rowno
            lineno = err.lineno
            cols = (colsvec...)
            @goto retry

        elseif err.err_code == POOL_OVERFLOW
            # promote refs to a wider integer type
            colsvec = Any[cols...]
            failcol = cols[err.colno]
            if debug[]
                println(STDERR, "Pool overflow.")
            end
            @assert isa(failcol, PooledArray)
            T = _widen(eltype(failcol.refs))
            newrefs = convert(Array{T}, failcol.refs)
            newcol = PooledArray(PooledArrays.RefArray(newrefs), failcol.pool)
            colsvec[err.colno] = newcol
            colspool[canonnames[err.colno]] = newcol
            rng = getlineat(str, err.fieldpos)

            cols = (colsvec...)
            pos = first(rng)
            rowno = err.rowno
            lineno = err.lineno
            @goto retry
        end

    end

    parsers = prev_parsers === nothing ? Dict() : copy(prev_parsers)
    for i in 1:length(rec.fields)
        name = get(canonnames, i, i)
        parsers[name] = rec.fields[i].inner
    end
    cols, canonnames, parsers, finalrows
end

function promote_field(failed_str, field, col, err, nastrings)
    newtoken = guesstoken(failed_str, field.inner, nastrings)
    if newtoken == field.inner
        # no need to change
        return field, col
    end
    newcol = try
        promote_column(col,  err.rowno-1, fieldtype(newtoken))
    catch err2
        Base.showerror(STDERR, err2)
        rethrow(err)
    end
    swapinner(field, newtoken), newcol
end

function promote_column(col, rowno, T, inner=false)
    if typeof(col) <: DataValueArray{Union{}}
        if T <: StringLike
            arr = Array{String, 1}(length(col))
            for i = 1:rowno
                arr[i] = ""
            end
            return arr
        elseif T <: DataValue
            DataValueArray(Array{eltype(T)}(length(col)), ones(Bool, length(col)))
        else
            error("empty to non-nullable")
        end
    elseif T <: DataValue
        if !isa(col, DataValueArray)
            isnullarray = Array{Bool}(length(col))
            isnullarray[1:rowno] = false
            isnullarray[(rowno+1):end] = true
            DataValueArray(promote_column(col, rowno, eltype(T)), isnullarray)
        else
            # Both input and output are nullable arrays
            vals = promote_column(col.values, rowno, eltype(T))
            DataValueArray(vals, col.isnull)
        end
    else
        @assert !isa(col, PooledArray) # Pooledarray of strings should never fail
        newcol = Array{T, 1}(length(col))
        copy!(newcol, 1, col, 1, rowno)
        newcol
    end
end

function readcolnames(str, opts, pos, colnames)
    colnames_inferred = String[]

    len = endof(str)
    lineend = getlineend(str, pos, len)
    head = str[pos:lineend]

    colnames_inferred = quotedsplit(str, opts, false, pos, lineend)
    # TODO: unescape

    # set a subset of column names
    for (i, v) in optionsiter(colnames, colnames_inferred)
        colnames_inferred[i] = v
    end
    colnames_inferred, lineend+1
end


function guesscolparsers(str::AbstractString, header, opts::LocalOpts, pos::Int,
                       nrows::Int, colparsers, nastrings=NA_STRINGS, prevs=nothing)
    # Field type guesses
    guess = []
    prevfields = String[]

    givenkeys = !isempty(colparsers) ? first.(collect(optionsiter(colparsers, header))) : []
    for i=1:nrows
        pos, _ = eatnewlines(str, pos)
        if pos > endof(str)
            break
        end

        lineend = getlineend(str, pos)

        fields = quotedsplit(str, opts, true, pos, lineend)

        if i == 1
            guess = Any[Unknown() for i=1:length(fields)] # idk
            if prevs !== nothing && !isempty(header)
                # sometimes length(fields) can be != length(header).
                # this sucks!
                for i in 1:length(header)
                    i > length(fields) && break
                    guess[i] = get(prevs, header[i], Unknown())
                end
            end
        end

        # update guess
        for j in 1:length(guess)
            if j in givenkeys
                continue # user specified this
            end
            if length(fields) != length(guess)
                error("previous rows had $(length(guess)) fields but row $i has $(length(fields))")
            end
            try
                guess[j] = guesstoken(fields[j], guess[j], nastrings)
            catch err
                println(STDERR, "Error while guessing a common type for column $j")
                println(STDERR, "new value: $(fields[j]), prev guess was: $(guess[j])")
                if j > 1
                    println(STDERR, "prev value: $(fields[j-1])")
                end

                rethrow(err)
            end
        end
        prevfields = fields
        pos = lineend+1
    end

    # override guesses with user request
    for (i, v) in optionsiter(colparsers, header)
        guess[i] = tofield(v, opts)
    end
    guess, pos
end

function parsefill!(str::AbstractString, opts, rec::RecN{N}, nrecs, cols, colspool,
                    pos, lineno, rowno, l=endof(str)) where {N}
    pos, lines = eatnewlines(str, pos)
    lineno += lines
    pos <= l && while true
        prev_j = pos
        lineno += lines
        res = tryparsesetindex(rec, str, pos, l, cols, rowno, opts)
        if !issuccess(res)
            pos, fieldpos, colno, err_code = geterror(res)
            throw(CSVParseError(err_code, str, rec, lineno+1, rowno,
                                colno, pos, fieldpos))
        else
            pos = value(res)
        end

        pos, lines = eatnewlines(str, pos)
        lineno += lines

        if pos > l
            return rowno
        end
        rowno += 1
        lineno += 1
        if rowno > nrecs
            # grow
            nrecs = ceil(Int, rowno * sqrt(2)) # updated estimate
            resizecols(colspool, nrecs)
        end
    end
    return rowno # finished before starting
end

function resizecols(colspool, nrecs)
    for (h, c) in colspool
        l = length(c)
        resize!(c, nrecs)
        if eltype(c) <: AbstractString
            # fill with blanks
            c[l+1:nrecs] = ""
        elseif eltype(c) <: StrRange
            c[l+1:nrecs] = StrRange(1,0)
        end
    end
end

function makeoutputvecs(rec, N, pooledstrings)
    map(f->makeoutputvec(f, N, pooledstrings), rec.fields)
end

function makeoutputvec(eltyp, N, pooledstrings)
    if fieldtype(eltyp) == DataValue{Union{}} # we weren't able to detect the type,
                                         # all columns were blank
        DataValueArray{Union{}}(N)
    elseif fieldtype(eltyp) == StrRange
      # By default we put strings in a PooledArray
      if pooledstrings
          resize!(PooledArray(PooledArrays.RefArray(UInt8[]), String[]), N)
      else
          Array{String}(N)
      end
    elseif fieldtype(eltyp) == DataValue{StrRange}
        DataValueArray{String}(N)
    elseif fieldtype(eltyp) <: DataValue
        DataValueArray{fieldtype(eltyp)|>eltype}(N)
    else
        Array{fieldtype(eltyp)}(N)
    end
end


mutable struct CSVParseError <: Exception
    err_code
    location_display
    rec
    lineno
    rowno
    colno
    pos
    fieldpos
    charinline
    filename
end

function CSVParseError(e_code, str, rec, lineno, rowno, colno, pos, fieldpos)
    rng = getlineat(str, pos)
    charinline = pos - first(rng)
    CSVParseError(e_code, showerrorchar(str, pos, 100), rec, lineno, rowno, colno, pos, fieldpos, charinline, nothing)
end


function Base.showerror(io::IO, err::CSVParseError)
    if err.filename !== nothing
        print(io, "CSV parsing error in $(err.filename) ")
    else
        print(io, "CSV parsing error ")
    end

    println(io, "at line $(err.lineno) char $(err.charinline):")
    println(io, err.location_display)
    print(io, "column $(err.colno) is expected to be: ")
    print(io, string(err.rec.fields[err.colno]))
end

function showerrorchar(str, pos, maxchar)
    hmaxchar = round(Int, maxchar/2)
    rng = getlineat(str, pos)
    substr = strip(str[rng])
    pointer = String(['_' for i=1:(pos-first(rng)-1)]) * "^"
    if length(substr) > maxchar
        # center the error char
        lst = min(pos+ceil(Int, hmaxchar), last(rng))
        fst = max(first(rng), pos-hmaxchar)
        substr = "..." * strip(str[fst:lst]) * "..."
        pointer = String(['_' for i=1:(pos-fst+2)]) * "^"
    end
    substr * "\n" * pointer
end

function quotedsplit(str, opts, includequotes, i=start(str), l=endof(str))
    strtok = Quoted(StringToken(String), required=false,
                    includequotes=includequotes)

    f = Field(strtok, eoldelim=true)
    strs = String[]
    if l == 0
        return strs
    end
    while i <= l # this means that there was an empty field at the end of the line
        @chk2 x, i = tryparsenext(f, str, i, l, opts)
        push!(strs, x)
    end
    c, i = next(str, prevind(str, i))
    if c == opts.endchar
        # edge case where there's a delim at the end of the string
        push!(strs, "")
    end

    return strs
    @label error
    error("Couldn't split line, error at char $i:\n$(showerrorchar(str, i, 100))")
end

function canonical_name(opts, name)
    for list in opts
        if name in list
            return first(list)
        end
    end
    return name
end
