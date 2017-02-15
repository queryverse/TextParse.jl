export csvread
const debugrec = Ref{Any}()

optionsiter(colnames::Associative) = colnames
optionsiter(colnames::AbstractVector) = enumerate(colnames)

tofield(f::AbstractField, opts) = f
tofield(f::AbstractToken, opts) =
    Field(f, delim=opts.delim, quotechar=opts.quotechar, escapechar=opts.escapechar)
tofield(t::Union{Type, DateFormat}, opts) =
    tofield(fromtype(t), opts)
tofield(t::Type{String}, opts) = 
    tofield(fromtype(StrRange), opts)
tofield(t::Type{Nullable{String}}, opts) =
    tofield(fromtype(Nullable{StrRange}), opts)

"""
    csvread(file::IO, delim=',';
            quotechar='"',
            escapechar='\\',
            dateformat=ISODateTimeFormat,
            header_exists=true,
            colnames=Dict(),
            coltypes=Dict(),
            type_detect_rows=20)

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

immutable ParsingOptions
    delim::Char
    quotechar::Char
    escapechar::Char
    #ignore_empty_rows::Bool
end

# read CSV in a string
function _csvread(str::AbstractString, delim=',';
                 quotechar='"',
                 escapechar='\\',
                 dateformats=common_date_formats,
                 datetimeformats=common_datetime_formats,
                 nrows=0,
                 header_exists=true,
                 colnames=String[],
                 #ignore_empty_rows=true,
                 coltypes=Type[],
                 type_detect_rows=20)

    opts = ParsingOptions(delim, quotechar, escapechar) #ignore_empty_rows,
    len = endof(str)
    pos = start(str)
    rowlength_sum = 0   # sum of lengths of rows, for estimating nrows

    if header_exists
        merged_colnames, pos = readcolnames(str, opts, pos, colnames)
    else
        merged_colnames = colnames
    end

    guess, pos1 = guesscoltypes(str, opts, pos, type_detect_rows, coltypes,
                          dateformats, datetimeformats)

    for (i, v) in enumerate(guess)
        guess[i] = tofield(v, opts)
    end

    guess[end].eoldelim = true
    rec = Record((guess...,))
    debugrec[] = rec

    if nrows == 0
        meanrowsize = (pos1-pos) / type_detect_rows
        # just an estimate, with some margin
        nrows = ceil(Int, (endof(str)-pos) / meanrowsize * sqrt(2))
    end

    cols = makeoutputvecs(str, rec, nrows)
    parsefill!(str, rec, nrows, cols, pos, endof(str))

    cols, merged_colnames
end

function readcolnames(str, opts, pos, colnames)
    colnames_inferred = String[]

    len = endof(str)
    pos = eatnewlines(str, pos, len)
    lineend = getlineend(str, pos, len)
    head = str[pos:lineend]

    colnames_inferred = map(strip, split(head, opts.delim))

    # set a subset of column names
    for (i, v) in optionsiter(colnames)
        colnames_inferred[i] = v
    end
    colnames_inferred, lineend+1
end


let
    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,1,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    opts = ParsingOptions(',', '"', '\\')
    @test readcolnames(str1, opts, 1, String[]) == (["a", "b", "c d", "e"], 13)
    @test readcolnames("\n\r$str1", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "e"], 15)
end

function guesscoltypes(str::AbstractString, opts::ParsingOptions, pos::Int,
                       nrows::Int, coltypes,
                       dateformats=common_date_formats,
                       datetimeformats=common_datetime_formats)
    # Field type guesses
    guess = []

    for i=1:nrows
        pos = eatnewlines(str, pos)
        if pos > endof(str)
            break
        end

        lineend = getlineend(str, pos)
        row = str[pos:lineend]

        fields = map(strip, split(row, opts.delim))
        if i == 1
            guess = Any[Union{} for i=1:length(fields)] # idk
        end

        # update guess
        guess = Any[guess_eltype(f, g, StrRange, dateformats, datetimeformats)
                    for (f,g) in zip(fields, guess)]
        pos = lineend+1
    end

    # override guesses with user request
    for (i, v) in optionsiter(coltypes)
        guess[i] = coltypes[i]
    end
    guess, pos
end

let
    str1 = """
     a, b,c d, e
    x,1,1,1
    x,1,1,1
    x,1,1.,1
    x y,1.0,1,
    ,1.0,,1
    """
    opts = ParsingOptions(',', '"', '\\')
    _, pos = readcolnames(str1, opts, 1, String[])
    testtill(i, coltypes=[]) = guesscoltypes(str1, opts, pos, i, coltypes)
    @test testtill(0) |> first == Any[]
    @test testtill(1) |> first == Any[StrRange, Int, Int, Int]
    @test testtill(2) |> first == Any[StrRange, Int, Int, Int]
    @test testtill(3) |> first == Any[StrRange, Int, Float64, Int]
    @test testtill(4) |> first == Any[StrRange, Float64, Float64, Nullable{Int}]
    @test testtill(5) |> first == Any[Nullable{StrRange}, Float64, Nullable{Float64}, Nullable{Int}]
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

const weakrefstringrefs = WeakKeyDict()
function makeoutputvecs(str, rec, N)
    ([if fieldtype(f) == WeakRefString{UInt8}
        x = Array{fieldtype(f)}(N)
        weakrefstringrefs[x] = str
        x
    elseif fieldtype(f) == StrRange
        Array{String,1}(N)
    elseif fieldtype(f) == Nullable{StrRange}
        NullableArray{String}(N)
    elseif fieldtype(f) <: Nullable
        NullableArray{fieldtype(f)|>eltype}(N)
    else
        Array{fieldtype(f)}(N)
    end for f in rec.fields]...)
end

function getlineat(str, i)
    ii = prevind(str, i)
    line_start = i
    l = endof(str)
    while ii > 0 && !isnewline(str[ii])
        line_start = ii
        ii = prevind(str, line_start)
    end

    c, ii = next(str, i)
    line_end = i
    while !isnewline(c) && ii <= l
        line_end = ii
        c, ii = next(str, ii)
    end

    line_start:line_end
end

let
    str = "abc\ndefg"
    @test str[getlineat(str,1)] == "abc\n"
    @test str[getlineat(str,4)] == "abc\n"
    @test str[getlineat(str,5)] == "defg"
    @test str[getlineat(str,endof(str))] == "defg"
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
    maxchar = 100
    rng = getlineat(str, char)
    substr = strip(str[rng])
    pointer = String(['_' for i=1:(char-first(rng)-1)]) * "^"
    if length(substr) > maxchar
        # center the error char
        lst = min(char+ceil(Int, maxchar), last(rng))
        fst = max(start(rng), lst-maxchar)
        substr = "..." * strip(str[fst:lst]) * "..."
        pointer = String(['_' for i=1:(char-fst+2)]) * "^"
    end
    err = "Parse error at line $(err.lineno) (excl header) at char $(err.charinline):\n" *
           substr * "\n" * pointer * "\nCSV column $(err.err_field) is expected to be: " * string(err.rec.fields[err.err_field])
    print(io, err)
end

let

    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,1,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    data = (
            (NullableArray(["x", "","x","x y","x"], Bool[0,1,0,0,0]),
              ones(5),
              NullableArray(ones(5), Bool[0,0,0,0,1]),
              NullableArray(ones(Int,5), Bool[0,0,0,1,0]))
              , ["a", "b", "c d", "e"])
    _csvread(str1, ',')
    @test isequal(_csvread(str1, ','), data)
end
