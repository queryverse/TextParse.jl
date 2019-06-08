using DataStructures
using Mmap

ismissingtype(T) = Missing <: T
ismissingeltype(T) = missingtype(eltype(T))

const UnionMissing{T} = Union{Missing, T}

export csvread
const current_record = Ref{Any}()
const debug = Ref{Bool}(false)

const StringLike = Union{AbstractString, StrRange}

optionsiter(opts::AbstractDict) = opts
optionsiter(opts::AbstractVector) = enumerate(opts)

getbyheader(opts, header, i::Int) = opts[i]
getbyheader(opts, header, i::Symbol) = getbyheader(opts, header, string(i))
function getbyheader(opts, header, i::AbstractString)
    if !(i in header)
        throw(ArgumentError("Unknown column $i"))
    end
    getbyheader(opts, header, something(findfirst(isequal(i), header), length(header)+1))
end

function optionsiter(opts::AbstractDict, header)
    isempty(header) && return opts
    iter = Dict{Int,Any}()
    for (k, v) in opts
        i = try
            getbyheader(1:length(header), header, k)
        catch err
            if isa(err, ArgumentError)
                continue
            else
                rethrow(err)
            end
        end
        iter[i] = v
    end
    iter
end

optionsiter(opts::AbstractVector, header) = optionsiter(opts)

tofield(f::AbstractField, opts, stringarraytype) = f
tofield(f::AbstractToken, opts, stringarraytype) = Field(f)
tofield(f::StringToken, opts, stringarraytype) = Field(Quoted(f, opts.quotechar, opts.escapechar))
tofield(f::Type, opts, stringarraytype) = tofield(fromtype(f), opts, stringarraytype)
tofield(f::Type{String}, opts, stringarraytype::Type{StringArray}) = tofield(fromtype(StrRange), opts, stringarraytype)
tofield(f::Type{String}, opts, stringarraytype::Type{Array}) = tofield(fromtype(String), opts, stringarraytype)
tofield(f::DateFormat, opts, stringarraytype) = tofield(DateTimeToken(DateTime, f), opts, stringarraytype)
tofield(f::Nothing, opts, stringarraytype) = Field(SkipToken(Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)))

"""
    csvread(file::Union{String,IO}, delim=','; <arguments>...)

Read CSV from `file`. Returns a tuple of 2 elements:
1. A tuple of columns each either a `Vector`, or `StringArray`
2. column names if `header_exists=true`, empty array otherwise

# Arguments:

- `file`: either an IO object or file name string
- `delim`: the delimiter character
- `spacedelim`: (Bool) parse space-delimited files. `delim` has no effect if true.
- `quotechar`: character used to quote strings, defaults to `"`
- `escapechar`: character used to escape quotechar in strings. (could be the same as quotechar)
- `commentchar`: ignore lines that begin with commentchar
- `nrows`: number of rows in the file. Defaults to `0` in which case we try to estimate this.
- `skiplines_begin`: skips specified number of lines at the beginning of the file
- `header_exists`: boolean specifying whether CSV file contains a header
- `nastrings`: strings that are to be considered NA. Defaults to `TextParse.NA_STRINGS`
- `colnames`: manually specified column names. Could be a vector or a dictionary from Int index (the column) to String column name.
- `colparsers`: Parsers to use for specified columns. This can be a vector or a dictionary from column name / column index (Int) to a "parser". The simplest parser is a type such as Int, Float64. It can also be a `dateformat"..."`, see [CustomParser](@ref) if you want to plug in custom parsing behavior. If you pass `nothing` as the parser for a given column, that column will be skipped
- `type_detect_rows`: number of rows to use to infer the initial `colparsers` defaults to 20.
"""
function csvread(file::String, delim=','; kwargs...)
    cols, canonnames, parsers, finalrows = _csvread_f(file, delim; kwargs...)

    return ((col for col in cols if col!==nothing)...,), [colname for (col, colname) in zip(cols, canonnames) if col!==nothing]
end

function csvread(file::IOStream, delim=','; kwargs...)
    mmap_data = Mmap.mmap(file)
    try
        _csvread(VectorBackedUTF8String(mmap_data), delim; kwargs...)
    finally
        finalize(mmap_data)
    end
end

function csvread(buffer::IO, delim=','; kwargs...)
    _csvread(String(read(buffer)), delim; kwargs...)
end

function _csvread(str::AbstractString, delim=','; kwargs...)
    cols, canonnames, parsers, finalrows = _csvread_internal(str, delim; kwargs...)

    return ((col for col in cols if col!==nothing)...,), [colname for (col, colname) in zip(cols, canonnames) if col!==nothing]
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
            try
                _csvread_internal(VectorBackedUTF8String(data), delim; filename=file, kwargs...)
            finally
                finalize(data)
            end
        end
    end
end

const ColsPool = OrderedDict{Union{Int, String}, Union{AbstractVector, Nothing}}

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
        println(stderr, "Error parsing $(files[1])")
        rethrow(err)
    end

    count = Int[nrows]
    prev = nrows
    for f in files[2:end]
        if !isempty(cols) && length(cols[findfirst(i->i!==nothing, cols)]) == nrows
            n = ceil(Int, nrows * sqrt(2))
            resizecols(colspool, n)
        end
        cols, headers, parsers, nrows = try
            _csvread_f(f, delim; rowno=nrows+1, colspool=colspool,
                       prevheaders=headers, noresize=true, prev_parsers=parsers, kwargs...)
        catch err
            println(stderr, "Error parsing $(f)")
            rethrow(err)
        end
        push!(count, nrows - prev)
        prev = nrows
    end

    resizecols(colspool, nrows)
    ((i[2] for i in colspool if i[2]!==nothing)...,), [i[1] for i in colspool if i[2]!==nothing], count
end

# read CSV in a string
function _csvread_internal(str::AbstractString, delim=',';
                 spacedelim=false,
                 quotechar='"',
                 escapechar='"',
                 commentchar=nothing,
                 stringtype=String,
                 stringarraytype=StringArray,
                 noresize=false,
                 rowno::Int=1,
                 prevheaders=nothing,
                 pooledstrings=nothing,
                 skiplines_begin=0,
                 samecols=nothing,
                 header_exists=true,
                 nastrings=NA_STRINGS,
                 colnames=String[],
                 #ignore_empty_rows=true,
                 colspool = ColsPool(),
                 nrows = !isempty(colspool) ?
                     length(first(i for i in colspool if i[2]!==nothing)[2]) : 0,
                 prev_parsers = nothing,
                 colparsers=[],
                 filename=nothing,
                 type_detect_rows=20)

    if pooledstrings === true
        @warn("pooledstrings argument has been removed")
    end
    opts = LocalOpts(isascii(delim) ? UInt8(delim) : delim, spacedelim,
        isascii(quotechar) ? UInt8(quotechar) : quotechar,
        isascii(escapechar) ? UInt8(escapechar) : escapechar, false, false)
    len = lastindex(str)
    pos = firstindex(str)
    rowlength_sum = 0   # sum of lengths of rows, for estimating nrows
    lineno = 0

    y = iterate(str, pos)
    if y!==nothing
        c = y[1]; i = y[2]
        if c == '\ufeff'
            pos = i
        end
    end

    pos, lines = eatnewlines(str, pos)
    lineno += lines
    while lineno < skiplines_begin
        pos = getlineend(str, pos)
        y2 = iterate(str, pos)
        y2===nothing && error("Internal error.")
        pos = y2[2]
        pos, lines = eatnewlines(str, pos)
        lineno += lines
    end

    # Ignore commented lines before the header.
    pos, lines = eatcommentlines(str, pos, len, commentchar)
    lineno += lines

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

    if length(unique(canonnames)) != length(canonnames)
        error("""File has multiple column headers with the same name, specify `colnames` by hand
                 along with `header_exists=false`""")
    end

    # seed guesses using those from previous file
    guess, pos1 = guesscolparsers(str, canonnames, opts,
                                  pos, type_detect_rows, colparsers, stringarraytype,
                                  commentchar, nastrings, prev_parsers)
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
        p = tofield(v, opts, stringarraytype)
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
        nrows = ceil(Int, (len-pos) / ((pos1-pos)/max(1, type_detect_rows)) * sqrt(2))
    end

    if isempty(colspool)
        # this is the first file, use nrows
        cols = makeoutputvecs(rec, nrows, stringtype, stringarraytype)
        for (c2, h) in zip(cols, canonnames)
            colspool[h] = c2
        end
    else
        _cols = map(1:length(rec.fields)) do i
            c = get(canonnames, i, i)
            f = rec.fields[i]
            if haskey(colspool, c)
                if eltype(colspool[c]) == fieldtype(f) || (fieldtype(f) <: StrRange && eltype(colspool[c]) <: AbstractString) || colspool[c]===nothing
                    return colspool[c]
                else
                    try
                        return colspool[c] = promote_column(colspool[c],
                                                            rowno-1,
                                                            fieldtype(f), stringtype, stringarraytype)
                    catch err
                        error("Could not convert column $c of eltype $(eltype(colspool[c])) to eltype $(fieldtype(f))")
                    end
                end
            else
                return colspool[c] = makeoutputvec(f, nrows, stringtype, stringarraytype)
            end
        end
        # promote missing columns to nullable
        missingcols = setdiff(collect(keys(colspool)), canonnames)
        for k in missingcols
            if !ismissingtype(eltype(colspool[k])) && !(eltype(colspool[k]) <: StringLike)
                colspool[k] = promote_column(colspool[k],
                                             rowno-1,
                                             UnionMissing{eltype(colspool[k])}, stringtype, stringarraytype)
            end
        end
        cols = (_cols...,)
    end

    if any(c->c!==nothing && length(c) != nrows, cols)
        resizecols(colspool, nrows)
    end

    finalrows = rowno
    @label retry
    try
        finalrows = parsefill!(str, opts, rec, nrows, cols, colspool,
                               pos, lineno, rowno, lastindex(str), commentchar)
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

            if l !== lastindex(str) && err.pos >= l && !field.eoldelim
                if fieldtype(field) <: AbstractString || fieldtype(field) <: StrRange
                    # retry assuming newlines can be part of the field
                    wopts = LocalOpts(opts.endchar, opts.spacedelim, opts.quotechar, opts.escapechar, opts.includequotes, true)
                    fieldsvec = Any[rec.fields...]
                    fieldsvec[err.colno] = swapinner(field, WrapLocalOpts(wopts, field.inner))
                    rec = Record((fieldsvec...,))
                    pos = first(rng)
                    rowno = err.rowno
                    lineno = err.lineno
                    current_record[] = rec
                    @goto retry
                end
                println(stderr, "Expected another field on row $(err.rowno) (line $(err.lineno))")
                err.filename = filename
                rethrow(err)
            end

            # figure out a new token type for this column and the rest
            # it's very likely that a number of columns change type in a single row
            # so we promote all columns after the failed column
            failed_strs = quotedsplit(str[err.fieldpos:l], opts, true)

            if length(failed_strs) != length(cols[err.colno:end])
                fn = err.filename === nothing ? "" : "In $(err.filename) "
                @warn("$(fn)line $(err.lineno) has $(length(err.colno) + length(failed_strs) - 1) fields but $(length(cols)) fields are expected. Skipping row.")
                pos = last(rng)+1
                rowno = err.rowno
                lineno = err.lineno+1
                @goto retry
            end
            promoted = map(failed_strs, err.colno:length(cols)) do s, colidx
                col = cols[colidx]
                f = rec.fields[colidx]
                name = get(canonnames, colidx, colidx)
                c = promote_field(s, f, col, err, nastrings, stringtype, stringarraytype, opts)
                colspool[name] = c[2]
                c
            end

            newfields = map(first, promoted)
            newcols = map(last, promoted)

            if field.inner == newfields[1].inner
                println(stderr, "Could not determine which type to promote column to.")
                rethrow(err)
            end

            fieldsvec = Any[rec.fields...]
            fieldsvec[err.colno:end] = newfields
            typeof(cols)
            colsvec = Any[cols...]
            colsvec[err.colno:end] = newcols

            rec = Record((fieldsvec...,))
            cols = (colsvec...,)
            rowno = err.rowno
            lineno = err.lineno
            pos = first(rng)
            current_record[] = rec
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

function promote_field(failed_str, field, col, err, nastrings, stringtype, stringarraytype, opts)
    if field.inner isa SkipToken
        # No need to change
        return field, col
    end
    newtoken = guesstoken(failed_str, opts, false, field.inner, nastrings, stringarraytype)
    if newtoken == field.inner
        # no need to change
        return field, col
    end
    newcol = try
        promote_column(col,  err.rowno-1, fieldtype(newtoken), stringtype, stringarraytype)
    catch err2
        # TODO Should this really be shown?
        Base.showerror(stderr, err2)
        println(stderr)
        rethrow(err)
    end
    swapinner(field, newtoken), newcol
end

function promote_column(col, rowno, T, stringtype, stringarraytype, inner=false)
    if typeof(col) <: Array{Missing}
        if T <: StringLike
            arr = stringarraytype{stringtype,1}(undef, length(col))
            for i = 1:rowno
                arr[i] = ""
            end
            return arr
        elseif ismissingtype(T)
            fill!(Array{UnionMissing{eltype(T)}}(undef, length(col)), missing) # defaults to fill missing
        else
            error("empty to non-nullable")
        end
    elseif ismissingtype(T)
        arr = convert(Array{UnionMissing{T}}, col)
        for i=rowno+1:length(arr)
            # if we convert an Array{Int} to be missing-friendly, we will not have missing in here by default
            arr[i] = missing
        end
        return arr
    else
        newcol = Array{T, 1}(undef, length(col))
        copyto!(newcol, 1, col, 1, rowno)
        newcol
    end
end

function readcolnames(str, opts, pos, colnames)
    colnames_inferred = String[]

    len = lastindex(str)
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
                       nrows::Int, colparsers, stringarraytype, commentchar=nothing, nastrings=NA_STRINGS, prevs=nothing)
    # Field type guesses
    guess = []
    prevfields = String[]

    givenkeys = !isempty(colparsers) ? first.(collect(optionsiter(colparsers, header))) : []
    for i2=1:nrows
        pos, _ = eatnewlines(str, pos)

        # Move past commented lines before guessing.
        pos, _ = eatcommentlines(str, pos, lastindex(str), commentchar)
        pos > lastindex(str) && break

        lineend = getrowend(str, pos, lastindex(str), opts, opts.endchar)

        fields = quotedsplit(str, opts, true, pos, lineend)

        if i2 == 1
            guess = Any[Unknown() for i3=1:length(fields)] # idk
            if prevs !== nothing && !isempty(header)
                # sometimes length(fields) can be != length(header).
                # this sucks!
                for i4 in 1:length(header)
                    i4 > length(fields) && break
                    guess[i4] = get(prevs, header[i4], Unknown())
                end
            end
        end

        # update guess
        for j in 1:length(guess)
            if j in givenkeys
                continue # user specified this
            end
            if length(fields) != length(guess)
                error("previous rows had $(length(guess)) fields but row $i2 has $(length(fields))")
            end
            try
                guess[j] = guesstoken(fields[j], opts, false, guess[j], nastrings, stringarraytype)
            catch err
                println(stderr, "Error while guessing a common type for column $j")
                println(stderr, "new value: $(fields[j]), prev guess was: $(guess[j])")
                if j > 1
                    println(stderr, "prev value: $(fields[j-1])")
                end

                rethrow(err)
            end
        end
        prevfields = fields
        pos = lineend+1
    end

    # override guesses with user request
    for (i, v) in optionsiter(colparsers, header)
        guess[i] = tofield(v, opts, stringarraytype)
    end
    guess, pos
end

function parsefill!(str::AbstractString, opts, rec::RecN{N}, nrecs, cols, colspool,
                    pos, lineno, rowno, l=lastindex(str), commentchar=nothing) where {N}
    pos, lines = eatnewlines(str, pos, l)
    lineno += lines

    pos <= l && while true
        prev_j = pos
        lineno += lines

        # Do not try to parse commented lines.
        pos, lines = eatcommentlines(str, pos, l, commentchar)
        lineno += lines
        pos > l && return rowno-1

        res = tryparsesetindex(rec, str, pos, l, cols, rowno, opts)
        if !issuccess(res)
            pos, fieldpos, colno, err_code = geterror(res)
            throw(CSVParseError(err_code, str, rec, lineno+1, rowno,
                                colno, pos, fieldpos))
        else
            pos = value(res)
        end

        pos, lines = eatnewlines(str, pos, l)
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
        if c!==nothing
            l = length(c)
            resize!(c, nrecs)
            if eltype(c) <: AbstractString
                # fill with blanks
                c[l+1:nrecs] .= ""
            elseif eltype(c) <: StrRange
                c[l+1:nrecs] .= StrRange(1,0)
            end
        end
    end
end

function makeoutputvecs(rec, N, stringtype, stringarraytype)
    map(f->makeoutputvec(f, N, stringtype, stringarraytype), rec.fields)
end

function makeoutputvec(eltyp, N, stringtype, stringarraytype)
    if fieldtype(eltyp)===Nothing
        return nothing
    elseif fieldtype(eltyp) == Missing # we weren't able to detect the type,
                                   # all cells were blank
        Array{Missing}(undef, N)
    elseif fieldtype(eltyp) == StrRange
        stringarraytype{stringtype,1}(undef, N)
    elseif ismissingtype(fieldtype(eltyp)) && fieldtype(eltyp) <: StrRange
        stringarraytype{Union{Missing, String},1}(undef, N)
    else
        Array{fieldtype(eltyp)}(undef, N)
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
        lst = thisind(str, min(pos+ceil(Int, hmaxchar), last(rng)))
        fst = thisind(str, max(first(rng), pos-hmaxchar))
        substr = "..." * strip(str[fst:lst]) * "..."
        pointer = String(['_' for i=1:(pos-fst+2)]) * "^"
    end
    substr * "\n" * pointer
end

function quotedsplit(str, opts, includequotes, i=firstindex(str), l=lastindex(str))
    strtok = Quoted(StringToken(String), opts.quotechar, opts.escapechar, required=false,
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
    y1 = iterate(str, prevind(str, i))
    y1===nothing && error("Internal error.")
    c = y1[1]; i = y1[2]
    if c == Char(opts.endchar)
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
