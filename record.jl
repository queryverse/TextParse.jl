immutable Record{Tf<:Tuple, To,N}
    fields::Tf
    use::NTuple{N,Int}
end

function Record{T<:Tuple}(t::T, use=())
    To = Tuple{subtuple(Any, map(fieldtype, t), use)...}
    #Tov = Tuple{map(s->Vector{s},map(fieldtype, t))...}
    Record{T, To, length(use)}(t, use)
end

@inline function subtuple{N}(T, t, idx::NTuple{N})
    ntuple(i -> t[idx[i]], Val{N})::T
end

@inline function subtuple(T, t, idx::Tuple{})
    t::T
end

@generated function tryparsenext{N,To,M}(r::Record{NTuple{N},To,M}, str, i, len)
    quote
        R = Nullable{To}
        i > len && @goto error

        Base.@nexprs $N j->begin
            @chk2 (val_j, i) = tryparsenext(r.fields[j], str, i, len)
        end

        res = subtuple(To, (Base.@ntuple $N val), r.use)

        @label done
        return R(res), i

        @label error
        R(), i
    end
end

@generated function tryparsesetindex{N,To,M}(r::Record{NTuple{N},To,M}, str, i, len, columns::NTuple{M}, row)
    quote
        R = Nullable{Void}
        i > len && @goto error

        Base.@nexprs $N j->begin
            @chk2 val_j, i = tryparsenext(r.fields[j], str, i, len)
        end

        res = subtuple(To, (Base.@ntuple $N val), r.use)

        Base.@nexprs $M j->begin
            columns[j][row] = res[j]
        end

        @label done
        return R(nothing), i

        @label error
        R(), i
    end
end

using Base.Test
let
    unwrap(xs) = (get(xs[1]), xs[2:end]...)
    failedat(xs) = (@assert isnull(xs[1]); xs[2])
    r=Record((Field(Prim{Int}()), Field(Prim{UInt}()), Field(Prim{Float64}())))
    @test tryparsenext(r, "12,21,21,", 1, 9) |> unwrap == ((12, UInt(21), 21.0), 10)
    @test tryparsenext(r, "12,21.0,21,", 1, 9) |> failedat == 6
    s = "12   ,  21,  21.23,"
    @test tryparsenext(r, s, 1, length(s)) |> unwrap == ((12, UInt(21), 21.23), length(s)+1)

    r2 = Record(r.fields, (1,3))
    @test tryparsenext(r2, "12,21,21,", 1, 9) |> unwrap == ((12, 21.0), 10)
    nothing
end
