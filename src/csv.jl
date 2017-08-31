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

# read CSV in a string
function _csvread(str::AbstractString, delim=',';
                 quotechar='"',
                 escapechar='\\',
                 dateformats=common_date_formats,
                 datetimeformats=common_datetime_formats,
                 pooledstrings=true,
                 nrows=0,
                 skiplines_begin=0,
                 header_exists=true,
                 colnames=String[],
                 #ignore_empty_rows=true,
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

    guess, pos1 = guesscolparsers(str, merged_colnames, opts, pos, type_detect_rows, colparsers,
                          dateformats, datetimeformats)

    for (i, v) in enumerate(guess)
        guess[i] = tofield(v, opts)
    end

    # the last field is delimited by line end
    guess[end] = Field(guess[end]; eoldelim = true)
    rec = Record((guess...,))
    current_record[] = rec

    if nrows == 0
        meanrowsize = (pos1-pos) / type_detect_rows
        # just an estimate, with some margin
        nrows = ceil(Int, (endof(str)-pos) / meanrowsize * sqrt(2))
    end

    cols = makeoutputvecs(str, rec, nrows, pooledstrings)
    rowno = 1

    @label retry
    try
        parsefill!(str, opts, rec, nrows, cols, pos, lineno, rowno, endof(str))
    catch err

        if !isa(err, CSVParseError)
            rethrow(err)
        end

        if err.err_code == PARSE_ERROR

            rng = getlineat(str, err.fieldpos)
            f, l = first(rng), last(rng)
            if err.pos >= l && !err.rec.fields[err.colno].eoldelim
                println(STDERR, "Expected another field on row $(err.rowno) (line $(err.lineno))")
                rethrow(err)
            end
            field = rec.fields[err.colno]
            failed_text = quotedsplit(str[err.fieldpos:l], opts, true)[1]
            # figure out a new token type
            newtoken = guesstoken(failed_text, field.inner)

            if field.inner == newtoken
                println(STDERR, "Could not determine which type to promote column to.")
                rethrow(err)
            end

            if debug[]
                println(STDERR, "Converting column $(err.colno) to type $(newtoken) from $(field.inner) because it seems to have a different type:")
                println(STDERR, showerrorchar(str, err.pos, 100))
            end

            newcol = try
                promote_column(cols[err.colno],  err.rowno, fieldtype(newtoken))
            catch err2
                if debug[]
                    rethrow(err2)
                    Base.showerror(STDERR, err)
                else
                    rethrow(err)
                end
            end

            fieldsvec = Any[rec.fields...]
            fieldsvec[err.colno] = swapinner(field, newtoken)
            typeof(cols)
            colsvec = Any[cols...]
            colsvec[err.colno] = newcol

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
            rng = getlineat(str, err.fieldpos)

            cols = (colsvec...)
            pos = first(rng)
            rowno = err.rowno
            lineno = err.lineno
            @goto retry
        end

    end

    cols, merged_colnames
end

function promote_column(col, rowno, T, inner=false)
    if typeof(col) <: NullableArray{Union{}}
        if T <: StringLike
            arr = Array{String, 1}(length(col))
            for i = 1:rowno-1
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
            isnullarray[1:rowno-1] = false
            isnullarray[rowno:end] = true
            NullableArray(promote_column(col, rowno, eltype(T)), isnullarray)
        else
            # Both input and output are nullable arrays
            vals = promote_column(col.values, rowno, eltype(T))
            NullableArray(vals, col.isnull)
        end
    else
        @assert !isa(col, PooledArray) # Pooledarray of strings should never fail
        newcol = Array{T, 1}(length(col))
        copy!(newcol, 1, col, 1, rowno-1)
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
                       nrows::Int, colparsers,
                       dateformats=common_date_formats,
                       datetimeformats=common_datetime_formats)
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
            guess = Any[Unknown() for i=1:length(fields)] # idk
        end

        # update guess
        for j in 1:length(guess)
            if length(fields) != length(guess)
                error("previous rows had $(length(guess)) fields but row $i has $(length(fields))")
            end
            try
                guess[j] = guesstoken(fields[j], guess[j])
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

function parsefill!{N}(str::AbstractString, opts, rec::RecN{N}, nrecs, cols,
                       pos, lineno, rowno, l=endof(str))
    sizemargin = sqrt(2)
    while true
        prev_j = pos
        pos, lines = eatnewlines(str, pos)
        lineno += lines + 1
        res = tryparsesetindex(rec, str, pos, l, cols, rowno, opts)
        if !issuccess(res)
            pos, fieldpos, colno, err_code = geterror(res)
            throw(CSVParseError(err_code, str, rec, lineno, rowno,
                                colno, pos, fieldpos))
        else
            pos = value(res)
        end

        if pos > l
            #shrink
            for c in cols
                resize!(c, rowno)
            end
            return cols
        end
        rowno += 1
        if rowno > nrecs
            # grow
            sizemargin = (sizemargin-1.0)/2 + 1.0
            nrecs = ceil(Int, (endof(str) / pos) * rowno * sizemargin) # updated estimate
            growcols(cols, nrecs)
        end
    end
end

function growcols(cols, nrecs)
    for c in cols
        resize!(c, nrecs)
    end
end

function makeoutputvecs(str, rec, N, pooledstrings)
    map(f->makeoutputvec(str, f, N, pooledstrings), rec.fields)
end

function makeoutputvec(str, eltyp, N, pooledstrings)
    if fieldtype(eltyp) == Nullable{Union{}} # we weren't able to detect the type,
                                         # all columns were blank
        NullableArray{Union{}}(N)
    elseif fieldtype(eltyp) == StrRange
      # By default we put strings in a PooledArray
      if pooledstrings
          resize!(PooledArray(PooledArrays.RefArray(UInt8[]), String[]), N)
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
    str
    rec
    lineno
    rowno
    colno
    pos
    fieldpos
end

function Base.showerror(io::IO, err::CSVParseError)
    str = err.str
    pos = err.pos

    rng = getlineat(str, pos)
    charinline = err.pos - first(rng)
    err = "Parse error at line $(err.lineno) at char $charinline:\n" *
            showerrorchar(str, pos, 100) *
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
