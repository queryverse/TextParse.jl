immutable Record{Tf<:Tuple, To}
    fields::Tf
end

function Record{T<:Tuple}(t::T)
    To = Tuple{map(fieldtype, t)...}
    #Tov = Tuple{map(s->Vector{s},map(fieldtype, t))...}
    Record{T, To}(t)
end

# for dispatch on N
if VERSION >= v"0.6.0-dev"
    eval(parse("typealias RecN{N,U} Record{T,U} where T<:NTuple{N, Any}"))
else
    typealias RecN{N,U} Record{NTuple{N}, U}
end

@generated function tryparsenext{N, To}(r::RecN{N, To}, str, i, len)
    quote
        R = Nullable{To}
        i > len && @goto error

        Base.@nexprs $N j->begin
            @chk2 (val_j, i) = tryparsenext(r.fields[j], str, i, len)
        end

        @label done
        return R(Base.@ntuple $N val), i

        @label error
        R(), i
    end
end

@generated function tryparsesetindex{N,To}(r::RecN{N,To}, str::AbstractString, i::Int, len::Int, columns::Tuple, row::Int)
    quote
        R = Result{Int, Tuple{Int,Int}}
        err_field = 1
        i > len && @goto error

        Base.@nexprs $N j->begin
            err_field = j
            @chk2 val_j, i = tryparsenext(r.fields[j], str, i, len)
            setcell!(columns[j], row, val_j, str)
        end

        @label done
        return R(true, i)

        @label error
        R(false, (i, err_field))
    end
end

@inline function setcell!(col, i, val, str)
    col[i] = val
end

@inline function setcell!{R}(col::PooledArray{String,R}, i, val::StrRange, str)
    nonallocating_setindex!(col, i, val, str)
end

@inline function setcell!(col::Array{String,1}, i, val::StrRange, str)
    col[i] = alloc_string(str, val)
end

@inline function setcell!(col::NullableArray{String,1}, i, val::Nullable{StrRange}, str)

    if isnull(val)
        col[i] = Nullable{String}()
    else
        sr = get(val)
        str = Nullable{String}(unsafe_string(pointer(str, 1+sr.offset), sr.length))
        col[i] = str
    end
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
function tryparsenext{T,S,use}(f::UseOne{T,S,use}, str, i, len)
    R = Nullable{T}
    @chk2 xs, i = tryparsenext(f.record, str, i, len)

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

@generated function tryparsenext{F,T,N}(f::Repeated{F,T,N}, str, i, len)
    quote
        R = Nullable{NTuple{N,T}}
        i > len && @goto error

        # pefect candidate for #11902
        Base.@nexprs $N j->begin
            @chk2 (val_j, i) = tryparsenext(f.field, str, i, len)
        end

        @label done
        return R(Base.@ntuple $N val), i

        @label error
        R(), i
    end
end
