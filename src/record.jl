struct Record{Tf<:Tuple, To}
    fields::Tf
end

function Record(t::T) where T<:Tuple
    To = Tuple{map(fieldtype, t)...}
    #Tov = Tuple{map(s->Vector{s},map(fieldtype, t))...}
    Record{T, To}(t)
end

# for dispatch on N
include_string(TextParse, "const RecN{N,U} = Record{T,U} where T<:NTuple{N, Any}")

@generated function tryparsenext(r::RecN{N, To}, str, i, len, opts=default_opts) where {N, To}
    quote
        R = Nullable{To}
        i > len && @goto error

        Base.@nexprs $N j->begin
            @chk2 (val_j, i) = tryparsenext(r.fields[j], str, i, len, opts)
        end

        @label done
        return R(Base.@ntuple $N val), i

        @label error
        R(), i
    end
end

const PARSE_SUCCESS = 0x00
const PARSE_ERROR   = 0x01

function gen_1parsesetindex(j, fieldexpr, colexpr)
    val_j = Symbol(:val, j)
    quote
        err_field = $j
        @chk2 $val_j, ii = tryparsenext($fieldexpr, str, i, len, opts)
        err = setcell!($colexpr, row, $val_j, str)
        if err != PARSE_SUCCESS
            err_code = err
            @goto error
        end
        i = ii
    end
end

@generated function tryparsesetindex(r::RecN{N,To}, str::AbstractString, i::Int, len::Int, columns::Tuple, row::Int, opts) where {N,To}
    fldtypes = Base.fieldtype(r, 1).parameters
    coltypes = columns.parameters
    fieldparsers = []
    j = 1
    while j <= N
        ft = fldtypes[j]
        ct = coltypes[j]
        rl = 1
        for k = j+1:N
            if fldtypes[k] == ft && coltypes[k] == ct
                rl += 1
            else
                break
            end
        end
        if rl > 2
            body = gen_1parsesetindex(:jj, :(r.fields[jj]::($ft)), :(columns[jj]::($ct)))
            push!(fieldparsers,
                  quote
                  for jj = $j:$(j+rl-1); $body; end
                  end)
            j += rl
        else
            push!(fieldparsers, gen_1parsesetindex(j, :(r.fields[$j]), :(columns[$j])))
            j += 1
        end
    end
    R = Result{Int, Tuple{Int,Int,Int,UInt8}}
    quote
        err_field = 1
        ii = i
        err_code = PARSE_ERROR
        i > len && @goto error

        $(fieldparsers...)

        @label done
        return $R(true, i)

        @label error
        $R(false, (ii, i, err_field, err_code)) # error char, start of error field, error field
    end
end

@inline function setcell!(col, i, val, str)
    col[i] = val
    PARSE_SUCCESS
end

@inline function setcell!(col::Nothing, i, val, str)
    PARSE_SUCCESS
end

@inline Base.@propagate_inbounds function setcell!(col::StringVector, i, val::StrRange, str)
    # TODO Properly handle the val.escapecount>0 case
    col[i] = WeakRefString(pointer(str, val.offset + 1), val.length)
    PARSE_SUCCESS
end

# Weird hybrid of records and fields

struct UseOne{T,R<:Record,use} <: AbstractToken{T}
    record::R
end

fieldtype(::UseOne{T}) where {T} = T

function UseOne(fields::Tuple, use)
    r = Record(fields)
    UseOne{fieldtype(fields[use]), typeof(r), use}(r)
end
getthing(x, ::Type{Val{n}}) where {n} = x[n]
function tryparsenext(f::UseOne{T,S,use}, str, i, len, opts=default_opts) where {T,S,use}
    R = Nullable{T}
    @chk2 xs, i = tryparsenext(f.record, str, i, len, opts)

    @label done
    return R(getthing(xs, Val{use})), i

    @label error
    return R(), i
end


struct Repeated{F, T, N}
    field::F
end

Repeated(f::F, n) where {F} = Repeated{F, fieldtype(f), n}(f)

fieldtype(::Repeated{F,T,N}) where {F,T,N} = NTuple{N,T}

@generated function tryparsenext(f::Repeated{F,T,N}, str, i, len, opts=default_opts) where {F,T,N}
    quote
        R = Nullable{NTuple{N,T}}
        i > len && @goto error

        # pefect candidate for #11902
        Base.@nexprs $N j->begin
            @chk2 (val_j, i) = tryparsenext(f.field, str, i, len, opts)
        end

        @label done
        return R(Base.@ntuple $N val), i

        @label error
        R(), i
    end
end
