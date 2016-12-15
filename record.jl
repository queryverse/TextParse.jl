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
            (val_j, i) = @chk1 tryparsenext(r.fields[j], str, i, len)
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
            val_j, i = @chk1 tryparsenext(r.fields[j], str, i, len)
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
    unwrap(xs) = (get(xs[1]), xs[2:end]...)
    failedat(xs) = (@assert isnull(xs[1]); xs[2])
    R = Nullable{Tuple{Int, UInt, Float64}}
    r=Record((Field(Prim{Int}()), Field(Prim{UInt}()), Field(Prim{Float64}())))
    @test tryparsenext(r, "12,21,21,", 1, 9) |> unwrap == ((12, UInt(21), 21.0), 10)
    @test tryparsenext(r, "12,21.0,21,", 1, 9) |> failedat == 6
    s = "12   ,  21,  21.23,"
    @test tryparsenext(r, s, 1, 9) |> unwrap == (R((12, 21, 21.23)), length(s)+1)
end
