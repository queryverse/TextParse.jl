using DataStructures

export csvread
const current_record = Ref{Any}()
const debug = Ref{Bool}(false)

const StringLike = Union{String, StrRange}

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
        iter[getbyheader(1:length(header), header, k)] = v
    end
    iter
end

optionsiter(opts::AbstractVector, header) = optionsiter(opts)

tofield(f::AbstractField, opts) = f
tofield(f::AbstractToken, opts) =
    Field(f, delim=opts.endchar)
tofield(f::StringToken, opts) =
    Field(Quoted(f), delim=opts.endchar)
tofield(f::Type, opts) = tofield(fromtype(f), opts)
tofield(f::Type{String}, opts) = tofield(fromtype(StrRange), opts)
tofield(f::DateFormat, opts) = tofield(DateTimeToken(DateTime, f), opts)

"""
    csvread(file::Union{String,IO}, delim=','; <arguments>...)

Read CSV from `file`. Returns a tuple of 2 elements:
1. A tuple of columns each either a `Vector`, `NullableArray` or `PooledArray`
2. column names if `header_exists=true`, empty array otherwise

# Arguments:

- `file`: either an IO object or file name string
- `delim`: the delimiter character
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
function csvread(file::String, delim=','; kwargs...)
    open(file, "r") do io
        csvread(io, delim; kwargs...)
    end
end

function csvread(file::IOStream, delim=','; kwargs...)
    mmap_data = Mmap.mmap(file)
    _csvread(WeakRefString(pointer(mmap_data), length(mmap_data)), delim; kwargs...)
end

function csvread(buffer::IO, delim=','; kwargs...)
    mmap_data = read(buffer)
    _csvread(WeakRefString(pointer(mmap_data), length(mmap_data)), delim; kwargs...)
end

function _csvread(str::AbstractString, delim=','; kwargs...)
    _csvread_internal(str, delim; kwargs...)[1:2]
end

function _csvread_f(file::AbstractString, delim=','; kwargs...)
    mmap_data = Mmap.mmap(file)
    _csvread_internal(WeakRefString(pointer(mmap_data), length(mmap_data)), delim; kwargs...)
end

const ColsPool = OrderedDict{Union{Int, String}, AbstractVector}

function csvread{T<:AbstractString}(files::AbstractVector{T},
                                    delim=','; kwargs...)
    @assert !isempty(files)
    colspool = ColsPool()
    cols, headers, rec, nrows = _csvread_f(files[1], delim;
                                           noresize=true,
                                           colspool=colspool,
                                           kwargs...)

    count = Int[nrows]
    prev = nrows
    for f in files[2:end]
        if length(cols[1]) == nrows
            n = ceil(Int, nrows * sqrt(2))
            resizecols(colspool, n)
        end
        cols, headers, rec, nrows = _csvread_f(f, delim; rowno=nrows+1, colspool=colspool,
                                               prevheaders=headers, noresize=true, rec=rec, kwargs...)
        push!(count, nrows - prev)
        prev = nrows
    end

    resizecols(colspool, nrows)
    (values(colspool)...), collect(keys(colspool)), count
end

# read CSV in a string
function _csvread_internal(str::AbstractString, delim=',';
                 quotechar='"',
                 escapechar='\\',
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
                 rec = nothing,
                 colparsers=[],
                 type_detect_rows=20)

    opts = LocalOpts(delim, quotechar, escapechar, false, false)
    len = endof(str)
    pos = start(str)
    rowlength_sum = 0   # sum of lengths of rows, for estimating nrows
    lineno = 0

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

    if rec === nothing || canonnames != prevheaders
        # this is the first file or has a different
        # format than the previous one

        prevs = rec !== nothing ? Dict(zip(prevheaders, map(x->x.inner, rec.fields))) : nothing
        guess, pos1 = guesscolparsers(str, canonnames, opts,
                                      pos, type_detect_rows, colparsers,
                                      nastrings, prevs)

        if isempty(canonnames)
            canonnames = Any[1:length(guess);]
        end

        for (i, v) in enumerate(guess)
            c = canonnames[i]
            # Make column nullable if it's showing up for the
            # first time, but not in the first file
            if rec !== nothing && !haskey(colspool, c)
                v = isa(v, NAToken) ? v : NAToken(v)
            end
            guess[i] = tofield(v, opts)
        end

        # the last field is delimited by line end
        guess[end] = Field(guess[end]; eoldelim = true)
        rec = Record((guess...,))
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
        _cols = map(canonnames, [rec.fields...]) do c, f
            if haskey(colspool, c)
                if eltype(colspool[c]) == fieldtype(f) || (fieldtype(f) <: StrRange && eltype(colspool[c]) <: AbstractString)
                    return colspool[c]
                else
                    return colspool[c] = promote_column(colspool[c],
                                                        rowno-1,
                                                        fieldtype(f))
                end
            else
                return colspool[c] = makeoutputvec(f, nrows, pooledstrings)
            end
        end
        # promote missing columns to nullable
        missingcols = setdiff(collect(keys(colspool)), canonnames)
        for k in missingcols
            if !(eltype(colspool[k]) <: Nullable)
                colspool[k] = promote_column(colspool[k],
                                             rowno-1,
                                             Nullable{eltype(colspool[k])})
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

        if err.err_code == PARSE_ERROR

            rng = getlineat(str, err.fieldpos)
            f, l = first(rng), last(rng)
            field = rec.fields[err.colno]

            if l !== endof(str) && err.pos >= l && !field.eoldelim
                if fieldtype(field) <: AbstractString || fieldtype(field) <: StrRange
                    # retry assuming newlines can be part of the field
                    wopts = LocalOpts(opts.endchar, opts.quotechar, opts.escapechar, opts.includequotes, true)
                    fieldsvec = Any[rec.fields...]
                    fieldsvec[err.colno] = swapinner(field, WrapLocalOpts(wopts, field.inner))
                    rec = Record((fieldsvec...))
                    pos = f
                    rowno = err.rowno
                    lineno = err.lineno
                    @goto retry
                end
                println(STDERR, "Expected another field on row $(err.rowno) (line $(err.lineno))")
                rethrow(err)
            end

            failed_strs = quotedsplit(str[err.fieldpos:l], opts, true)
            # figure out a new token type for this column and the rest
            # it's very likely that a number of columns change type in a single row
            promoted = map(failed_strs, [cols[err.colno:end]...], [rec.fields[err.colno:end]...], canonnames[err.colno:end]) do s, col, f, name
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
            pos = f
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
            newcol = PooledArray(PooledArrays.RefArray(newrefs), convert(Dict{eltype(failcol), T}, failcol.pool))
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

    cols, canonnames, rec, finalrows
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
        if debug[]
            rethrow(err2)
            Base.showerror(STDERR, err)
        else
            rethrow(err)
        end
    end
    swapinner(field, newtoken), newcol
end

function promote_column(col, rowno, T, inner=false)
    if typeof(col) <: NullableArray{Union{}}
        if T <: StringLike
            arr = Array{String, 1}(length(col))
            for i = 1:rowno
                arr[i] = ""
            end
            return arr
        elseif T <: Nullable
            NullableArray(Array{eltype(T)}(length(col)), zeros(Bool, length(col)))
        else
            error("empty to non-nullable")
        end
    elseif T <: Nullable
        if !isa(col, NullableArray)
            isnullarray = Array{Bool}(length(col))
            isnullarray[1:rowno] = false
            isnullarray[(rowno+1):end] = true
            NullableArray(promote_column(col, rowno, eltype(T)), isnullarray)
        else
            # Both input and output are nullable arrays
            vals = promote_column(col.values, rowno, eltype(T))
            NullableArray(vals, col.isnull)
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

    for i=1:nrows
        pos, _ = eatnewlines(str, pos)
        if pos > endof(str)
            break
        end

        lineend = getlineend(str, pos)

        fields = quotedsplit(str, opts, true, pos, lineend)
        if i == 1
            if prevs !== nothing && !isempty(header)
                guess = Any[get(prevs, h, Unknown()) for h in header]
            else
                guess = Any[Unknown() for i=1:length(fields)] # idk
            end
        end

        # update guess
        for j in 1:length(guess)
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

function parsefill!{N}(str::AbstractString, opts, rec::RecN{N}, nrecs, cols, colspool,
                       pos, lineno, rowno, l=endof(str))
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
end

function resizecols(colspool, nrecs)
    for (h, c) in colspool
        resize!(c, nrecs)
    end
end

function makeoutputvecs(rec, N, pooledstrings)
    map(f->makeoutputvec(f, N, pooledstrings), rec.fields)
end

function makeoutputvec(eltyp, N, pooledstrings)
    if fieldtype(eltyp) == Nullable{Union{}} # we weren't able to detect the type,
                                         # all columns were blank
        NullableArray{Union{}}(N)
    elseif fieldtype(eltyp) == StrRange
      # By default we put strings in a PooledArray
      if pooledstrings
          resize!(PooledArray(PooledArrays.RefArray(UInt8[]), Dict{String, UInt8}()), N)
      else
          Array{String}(N)
      end
    elseif fieldtype(eltyp) == Nullable{StrRange}
        NullableArray{String}(N)
    elseif fieldtype(eltyp) <: Nullable
        NullableArray{fieldtype(eltyp)|>eltype}(N)
    else
        Array{fieldtype(eltyp)}(N)
    end
end


immutable CSVParseError <: Exception
    err_code
    location_display
    rec
    lineno
    rowno
    colno
    pos
    fieldpos
    charinline
end

function CSVParseError(e_code, str, rec, lineno, rowno, colno, pos, fieldpos)
    rng = getlineat(str, pos)
    charinline = pos - first(rng)
    CSVParseError(e_code, showerrorchar(str, pos, 100), rec, lineno, rowno, colno, pos, fieldpos, charinline)
end


function Base.showerror(io::IO, err::CSVParseError)
    err = "Parse error at line $(err.lineno) at char $(err.charinline):\n" *
            err.location_display *
            "\nCSV column $(err.colno) is expected to be: " *
            string(err.rec.fields[err.colno])
    print(io, err)
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
