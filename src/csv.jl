export csvread

optionsiter(colnames::Associative) = colnames
optionsiter(colnames::AbstractVector) = enumerate(colnames)

tofield(f::Field, x,y,z) = f
tofield(t::Union{Type, DateFormat}, delim, quotechar,escapechar) =
    Field(fromtype(t), delim=delim, quotechar=quotechar, escapechar=escapechar)


function csvread(filename::String, delim=',';
                 quotechar='"',
                 escapechar='\\',
                 dateformat=ISODateTimeFormat,
                 header_exists=true,
                 colnames=String[],
                 coltypes=Type[],
                 strtype=WeakRefString{UInt8},
                 type_detect_rows=20)
    f=open(filename, "r")

    start_offset = 0
    rowlength_sum = 0
    if header_exists
        h = readline(f) # header
        start_offset = endof(h)+1

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

function parsefill!{N}(str::String, rec::Record{NTuple{N}}, nrecs, cols)
    i = 1
    j = start(str)
    l = endof(str)
    while true
        succ, j = tryparsesetindex(rec, str, j,l, cols, i)
        isnull(succ) && throw(ParseError("parse failed at $j"))
        if j > l
            #shrink
            for c in cols
                resize!(c, i)
            end
            return cols
        end
        i += 1
        if i > nrecs
            nrecs = round(Int, nrecs * sqrt(2))
            # grow
            nrecs = ceil(Int, j/i * sqrt(2)) # updated estimate
            for c in cols
                resize!(c, nrecs)
            end
        end
    end
end

const weakrefstringrefs = WeakKeyDict()
function makeoutputvecs(str, rec, N)
    ([if fieldtype(f) == WeakRefString{UInt8}
        x = Array(fieldtype(f), N)
        weakrefstringrefs[x] = str
        x
    elseif fieldtype(f) <: Nullable
        NullableArray(fieldtype(f), N)
    else
        Array(fieldtype(f), N)
    end for f in rec.fields]...)
end
