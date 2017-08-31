immutable Record{Tf<:Tuple, To}
    fields::Tf
end

function Record{T<:Tuple}(t::T)
    To = Tuple{map(fieldtype, t)...}
    #Tov = Tuple{map(s->Vector{s},map(fieldtype, t))...}
    Record{T, To}(t)
end

# for dispatch on N
if VERSION >= v"0.6.0-dev.2123" # new type system, julia PR #18457
    include_string("const RecN{N,U} = Record{T,U} where T<:NTuple{N, Any}")
else
    include_string("typealias RecN{N,U} Record{NTuple{N}, U}")
end

@generated function tryparsenext{N, To}(r::RecN{N, To}, str, i, len, opts=default_opts)
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
const POOL_CROWDED  = 0x02
const POOL_OVERFLOW = 0x03

@generated function tryparsesetindex{N,To}(r::RecN{N,To}, str::AbstractString, i::Int, len::Int, columns::Tuple, row::Int, opts)
    quote
        R = Result{Int, Tuple{Int,Int,Int,UInt8}}
        err_field = 1
        ii = i
        err_code = PARSE_ERROR
        i > len && @goto error

        Base.@nexprs $N j->begin
            err_field = j
            @chk2 val_j, ii = tryparsenext(r.fields[j], str, i, len, opts)
            err = setcell!(columns[j], row, val_j, str)
            if err != PARSE_SUCCESS
                err_code = err
                @goto error
            end
            i = ii
        end

        @label done
        return R(true, i)

        @label error
        R(false, (ii, i, err_field, err_code)) # error char, start of error field, error field
    end
end

@inline function setcell!(col, i, val, str)
    col[i] = val
    PARSE_SUCCESS
end

@inline function setcell!(col::NullableArray{Union{}}, i, val::Void, str)
    PARSE_SUCCESS
end

const MAX_POOL_FRACTION = 0.05
const ROWS_BEFORE_CROWDING = 400
@inline function setcell!{R}(col::PooledArray{String,R}, i, val::StrRange, str)
    if i > ROWS_BEFORE_CROWDING && length(col.pool) > i * MAX_POOL_FRACTION
        return POOL_CROWDED
    elseif length(col.pool) >= typemax(R)
        return POOL_OVERFLOW
    else
        nonallocating_setindex!(col, i, val, str)
        return PARSE_SUCCESS
    end
end

@inline function setcell!(col::Array{String,1}, i, val::StrRange, str)
    col[i] = alloc_string(str, val)
    PARSE_SUCCESS
end

# Weird hybrid of records and fields

immutable UseOne{T,R<:Record,use} <: AbstractToken{T}
    record::R
end

fieldtype{T}(::UseOne{T}) = T

function UseOne(fields::Tuple, use)
    r = Record(fields)
    UseOne{fieldtype(fields[use]), typeof(r), use}(r)
end
getthing{n}(x, ::Type{Val{n}}) = x[n]
function tryparsenext{T,S,use}(f::UseOne{T,S,use}, str, i, len, opts=default_opts)
    R = Nullable{T}
    @chk2 xs, i = tryparsenext(f.record, str, i, len, opts)

    @label done
    return R(getthing(xs, Val{use})), i

    @label error
    return R(), i
end


immutable Repeated{F, T, N}
    field::F
end

Repeated{F}(f::F, n) = Repeated{F, fieldtype(f), n}(f)

fieldtype{F,T,N}(::Repeated{F,T,N}) = NTuple{N,T}

@generated function tryparsenext{F,T,N}(f::Repeated{F,T,N}, str, i, len, opts=default_opts)
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
