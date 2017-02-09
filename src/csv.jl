export csvread

optionsiter(colnames::Associative) = colnames
optionsiter(colnames::AbstractVector) = enumerate(colnames)

tofield(f::Field, x,y,z) = f
tofield(t::Union{Type, DateFormat}, delim, quotechar,escapechar) =
    Field(fromtype(t), delim=delim, quotechar=quotechar, escapechar=escapechar)
tofield(t::Type{String}, delim, quotechar,escapechar) =
    Field(fromtype(StrRange), delim=delim, quotechar=quotechar, escapechar=escapechar)
tofield(t::Type{Nullable{String}}, delim, quotechar,escapechar) =
    Field(fromtype(Nullable{StrRange}), delim=delim, quotechar=quotechar, escapechar=escapechar)


function csvread(filename::String, delim=',';
                 quotechar='"',
                 escapechar='\\',
                 dateformat=ISODateTimeFormat,
                 header_exists=true,
                 colnames=String[],
                 coltypes=Type[],
                 strtype=StrRange,
                 type_detect_rows=20)
    f=open(filename, "r")

    start_offset = 0
    rowlength_sum = 0
    if header_exists
        h = readline(f) # header
        start_offset = endof(h) + (VERSION < v"0.6.0-dev" ? 0 : 1) # on 0.6 readline omits the \n

        if isempty(colnames)
            colnames_inferred = split(h, delim)
        else
            for (i, v) in optionsiter(colnames)
                colnames_inferred[i] = v
            end
        end
    end

    colnames_inferred = String[]
    guess = []
    if length(coltypes) != 0 && length(coltypes) == length(colnames)
        # we already know the types
        guess = coltypes
        @goto parse
    end

    for i=1:type_detect_rows
        str = readline(f) # header
        rowlength_sum += endof(str)
        if i == 1
            line = split(str, delim)
            guess = Any[Union{} for i=1:length(line)]
        end
        guess = Any[guess_eltype(x, y, strtype, dateformat) for (x,y) in
                    zip(split(str, delim), guess)]
    end
    rowlength_estimate = rowlength_sum / type_detect_rows
    rowestimate = ceil(Int, filesize(f) / rowlength_estimate)

    for (i, v) in optionsiter(coltypes)
        guess[i] = coltypes[i]
    end

    for (i, v) in enumerate(guess)
        guess[i] = tofield(v, delim, quotechar, escapechar)
    end

    guess[end].eoldelim = true

    @label parse
    rec = Record((guess...,))
    mmap_data = Mmap.mmap(seek(f, start_offset))
    close(f)
    str = String(mmap_data)
    N = round(Int, rowestimate * sqrt(2))
    cols = makeoutputvecs(str, rec, N)
    parsefill!(str, rec, N, cols)
end

function parsefill!{N}(str::String, rec::RecN{N}, nrecs, cols)
    i = 1
    j = start(str)
    l = endof(str)
    sizemargin = sqrt(2)
    while true
        prev_j = j
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
        Array{String}(N)
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
    str = "abc\ndefg"
    @test str[getlineat(str,1)] == "abc\n"
    @test str[getlineat(str,4)] == "abc\n"
    @test str[getlineat(str,5)] == "defg"
    @test str[getlineat(str,endof(str))] == "defg"
end
