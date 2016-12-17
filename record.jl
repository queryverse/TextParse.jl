immutable Record{Tf<:Tuple, To}
    fields::Tf
end

function Record{T<:Tuple}(t::T)
    To = Tuple{map(fieldtype, t)...}
    #Tov = Tuple{map(s->Vector{s},map(fieldtype, t))...}
    Record{T, To}(t)
end

@generated function tryparsenext{N,To}(r::Record{NTuple{N},To}, str, i, len)
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

@generated function tryparsesetindex{N,To}(r::Record{NTuple{N},To}, str, i, len, columns::Tuple, col)
    quote
        R = Nullable{Void}
        i > len && @goto error

        Base.@nexprs $N j->begin
            @chk2 val_j, i = tryparsenext(r.fields[j], str, i, len)
            columns[j][col] = val_j
        end

        @label done
        return R(nothing), i

        @label error
        R(), i
    end
end

using Base.Test
let
    r=Record((Field(Prim(Int)), Field(Prim(UInt)), Field(Prim(Float64))))
    @test tryparsenext(r, "12,21,21,", 1, 9) |> unwrap == ((12, UInt(21), 21.0), 10)
    @test tryparsenext(r, "12,21.0,21,", 1, 9) |> failedat == 6
    s = "12   ,  21,  21.23,"
    @test tryparsenext(r, s, 1, length(s)) |> unwrap == ((12, UInt(21), 21.23), length(s)+1)
    nothing
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


using Base.Test
let
    f = UseOne((Field(Prim(Int), delim=';'), Field(Prim(Float64)), Field(Prim(Int), eoldelim=true)), 3)
    @test tryparsenext(f, "1; 33.21, 45", 1, 12) |> unwrap == (45, 13)
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

using BenchmarkTools

let
    f = Repeated(Field(Prim(Int), delim=';'), 3)
    @test tryparsenext(f, "1; 33; 45;", 1, 12) |> unwrap == ((1,33,45), 11)

    inp = join(map(string, [1:45;]), "; ") * "; "
    out = ntuple(identity, 45)
    f2 = Repeated(Field(Prim(Int), delim=';'), 45)
    @test tryparsenext(f2, inp, 1, length(inp)) |> unwrap == (out, length(inp))
    #@benchmark tryparsenext($f2, $inp, 1, length($inp))
end
