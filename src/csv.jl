export csvread
const debugrec = Ref{Any}()

optionsiter(opts::Associative) = opts
optionsiter(opts::AbstractVector) = enumerate(opts)

getbyheader(opts, header, i::Int) = opts[i]
getbyheader(opts, header, i::Symbol) = getcol(opts, header, string(i))
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
tofield(f::Type, opts) = tofield(fromtype(f), opts)
tofield(f::DateFormat, opts) = tofield(DateTimeToken(DateTime, f), opts)

"""
    csvread(file::IO, delim=',';
            quotechar='"',
            escapechar='\\',
            dateformat=ISODateTimeFormat,
            header_exists=true,
            colnames=Dict(),
            coltypes=Dict(),
            type_detect_rows=100)

Read CSV from `file`. Returns a tuple of 2 elements:
1. A tuple of columns each as a Vector or NullableArray
2. column names if header_exists=true

Notes:
- `type_detect_rows` is the number of rows used to detect the type
  of the column. If the column changes type later, you must specify
  the right type in `coltypes`
- Empty lines will be ignored
"""
function csvread(file::String, delim=','; kwargs...)
    open(file, "r") do io
        csvread(io, delim; kwargs...)
    end
end

function csvread(file::IO, delim=','; kwargs...)
    mmap_data = Mmap.mmap(file)
    _csvread(String(mmap_data), delim; kwargs...)
end

# read CSV in a string
function _csvread(str::AbstractString, delim=',';
                 quotechar='"',
                 escapechar='\\',
                 dateformats=common_date_formats,
                 datetimeformats=common_datetime_formats,
                 pooledstrings=false,
                 nrows=0,
                 header_exists=true,
                 colnames=String[],
                 #ignore_empty_rows=true,
                 coltypes=Type[],
                 type_detect_rows=100)

    opts = LocalOpts(delim, quotechar, escapechar, false, false)
    len = endof(str)
    pos = start(str)
    rowlength_sum = 0   # sum of lengths of rows, for estimating nrows

    if header_exists
        merged_colnames, pos = readcolnames(str, opts, pos, colnames)
    else
        merged_colnames = colnames
    end

    guess, pos1 = guesscoltypes(str, merged_colnames, opts, pos, type_detect_rows, coltypes,
                          dateformats, datetimeformats)

    for (i, v) in enumerate(guess)
        guess[i] = tofield(v, opts)
    end

    guess[end].eoldelim = true # the last one is delimited by line end
    rec = Record((guess...,))
    debugrec[] = rec

    if nrows == 0
        meanrowsize = (pos1-pos) / type_detect_rows
        # just an estimate, with some margin
        nrows = ceil(Int, (endof(str)-pos) / meanrowsize * sqrt(2))
    end

    cols = makeoutputvecs(str, rec, nrows, pooledstrings)
    parsefill!(str, rec, nrows, cols, pos, endof(str))

    cols, merged_colnames
end

function readcolnames(str, opts, pos, colnames)
    colnames_inferred = String[]

    len = endof(str)
    pos = eatnewlines(str, pos, len)
    lineend = getlineend(str, pos, len)
    head = str[pos:lineend]

    colnames_inferred = quotedsplit(str, opts.endchar, opts.quotechar, opts.escapechar, false, pos, lineend)
    # TODO: unescape

    # set a subset of column names
    for (i, v) in optionsiter(colnames, colnames_inferred)
        colnames_inferred[i] = v
    end
    colnames_inferred, lineend+1
end


function guesscoltypes(str::AbstractString, header, opts::LocalOpts, pos::Int,
                       nrows::Int, coltypes,
                       dateformats=common_date_formats,
                       datetimeformats=common_datetime_formats)
    # Field type guesses
    guess = []
    prevfields = String[]

    for i=1:nrows
        pos = eatnewlines(str, pos)
        if pos > endof(str)
            break
        end

        lineend = getlineend(str, pos)

        fields = quotedsplit(str, opts.endchar, opts.quotechar, opts.escapechar, true, pos, lineend)
        if i == 1
            guess = Any[Unknown() for i=1:length(fields)] # idk
        end

        # update guess
        for j in 1:length(guess)
            if length(fields) != length(guess)
                error("previous rows had $(length(guess)) fields but row $i has $(length(fields))")
            end
            try
                guess[j] = guesstoken(fields[j], opts,
                                      guess[j], StrRange,
                                      dateformats, datetimeformats)
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
    for (i, v) in optionsiter(coltypes, header)
        guess[i] = tofield(v, opts)
    end
    guess, pos
end

function parsefill!{N}(str::String, rec::RecN{N}, nrecs, cols,
                       j=start(str), l=endof(str))
    i = 1
    sizemargin = sqrt(2)
    while true
        prev_j = j
        j = eatnewlines(str, j)
        res = tryparsesetindex(rec, str, j,l, cols, i)
        if !issuccess(res)
            j, tok = geterror(res)
            throw(CSVParseError(str, rec, i, j, j-prev_j, tok))
        else
            j = value(res)
        end

        if j > l
            #shrink
            for c in cols
                resize!(c, i)
            end
            return cols
        end
        i += 1
        if i > nrecs
            # grow
            sizemargin = (sizemargin-1.0)/2 + 1.0
            nrecs = ceil(Int, j/i * sizemargin) # updated estimate
            for c in cols
                resize!(c, nrecs)
            end
        end
    end
end

function makeoutputvecs(str, rec, N, pooledstrings)
    ([if fieldtype(f) == Nullable{Union{}} # we weren't able to detect the type, all columns were blank
        NullableArray{Void}(N)
    elseif fieldtype(f) == StrRange
      # By default we put strings in a PooledArray
      if pooledstrings
          resize!(PooledArray(Int32[], String[]), N)
      else
          Array{String}(N)
      end
    elseif fieldtype(f) == Nullable{StrRange}
        NullableArray{String}(N)
    elseif fieldtype(f) <: Nullable
        NullableArray{fieldtype(f)|>eltype}(N)
    else
        Array{fieldtype(f)}(N)
    end for f in rec.fields]...)
end


immutable CSVParseError <: Exception
    str
    rec
    lineno
    char
    charinline
    err_field
end

function Base.showerror(io::IO, err::CSVParseError)
    str = err.str
    char = err.char

    err = "Parse error at line $(err.lineno) (excl header) at char $(err.charinline):\n" *
            showerrorchar(str, char, 100) *
            "\nCSV column $(err.err_field) is expected to be: " *
            string(err.rec.fields[err.err_field])
    print(io, err)
end

function showerrorchar(str, char, maxchar)
    hmaxchar = round(Int, maxchar/2)
    rng = getlineat(str, char)
    substr = strip(str[rng])
    pointer = String(['_' for i=1:(char-first(rng)-1)]) * "^"
    if length(substr) > maxchar
        # center the error char
        lst = min(char+ceil(Int, hmaxchar), last(rng))
        fst = max(first(rng), char-hmaxchar)
        substr = "..." * strip(str[fst:lst]) * "..."
        pointer = String(['_' for i=1:(char-fst+2)]) * "^"
    end
    substr * "\n" * pointer
end

function quotedsplit(str, delim, quotechar, escapechar, includequotes, i, l)
    strtok = Quoted(StringToken(String),
                    required=false, escapechar=escapechar,
                    quotechar=quotechar,includequotes=includequotes)

    f = Field(strtok, delim=delim, eoldelim=true)
    strs = String[]
    while i <= l # this means that there was an empty field at the end of the line
        @chk2 x, i = tryparsenext(f, str, i, l)
        push!(strs, x)
    end
    c, i = next(str, prevind(str, i))
    if c == delim
        # edge case where there's a delim at the end of the string
        push!(strs, "")
    end

    return strs
    @label error
    error("Couldn't split line, error at char $i:\n$(showerrorchar(str, i, 100))")
end
