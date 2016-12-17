using QuickTypes

abstract AbstractToken{T}


### Simple primitive parsing
### parses just the thing of type T
immutable Prim{T} <: AbstractToken{T}
    delim::Char
end
Prim(T) = Prim{T}(',')

fieldtype{T}(::AbstractToken{T}) = T


### Unsigned integers

@inline function tryparsenext{T<:Unsigned}(::Prim{T}, str, i, len)
    tryparsenext_base10(T,str, i, len)
end

@inline function tryparsenext{T<:Signed}(::Prim{T}, str, i, len)
    R = Nullable{T}
    @chk2 sign, i = tryparsenext_sign(str, i, len)
    @chk2 x, i = tryparsenext_base10(T, str, i, len)

    @label done
    return R(sign*x), i

    @label error
    return R(), i
end

@inline function tryparsenext(::Prim{Float64}, str, i, len)
    R = Nullable{Float64}
    f = 0.0
    @chk2 sign, i = tryparsenext_sign(str, i, len)
    x=0

    i > len && @goto error
    c, ii = next(str, i)
    if c == '.'
        i=ii
        @goto dec
    end
    @chk2 x, i = tryparsenext_base10(Int, str, i, len)
    i > len && @goto done
    @inbounds c, ii = next(str, i)

    c != '.' && @goto done
    @label dec
    @chk2 y, i = tryparsenext_base10(Int, str, ii, len)
    f = y / 10.0^(i-ii)

    i > len && @goto done
    c, ii = next(str, i)
    if c == 'e' || c == 'E'
        @chk2 exp, i = tryparsenext(Prim(Int), str, ii, len)
        return R(sign*(x+f) * 10.0^exp), i
    end

    @label done
    return R(sign*(x+f)), i

    @label error
    return R(), i
end

using Base.Test
let
    @test tryparsenext(Prim(Float64), "21", 1, 2) |> unwrap== (21.0,3)
    @test tryparsenext(Prim(Float64), ".21", 1, 3) |> unwrap== (.21,4)
    @test tryparsenext(Prim(Float64), "1.21", 1, 4) |> unwrap== (1.21,5)
    @test tryparsenext(Prim(Float64), "-1.21", 1, 5) |> unwrap== (-1.21,6)
    @test tryparsenext(Prim(Float64), "-1.5e-12", 1, 8) |> unwrap == (-1.5e-12,9)
    @test tryparsenext(Prim(Float64), "-1.5E-12", 1, 8) |> unwrap == (-1.5e-12,9)
end

@inline function _substring(::Type{String}, str, i, j)
    str[i:j]
end

@inline function _substring{T}(::Type{SubString{T}}, str, i, j)
    SubString(str, i, j)
end

using WeakRefStrings
@inline function _substring{T}(::Type{WeakRefString{T}}, str, i, j)
    WeakRefString(pointer(str.data)+(i-1), (j-i+1))
end

function tryparsenext{T<:AbstractString}(p::Prim{T}, str, i, len)
    R = Nullable{T}
    @chk2 _, ii = tryparsenext_string(str, i, len, (p.delim,))

    @label done
    return R(_substring(T, str, i, ii-1)), ii

    @label error
    return R(), ii
end

function tryparsenext(p::Prim{Tuple{Int, Int}}, str, i, len)
    R = Nullable{Tuple{Int,Int}}
    @chk2 _, ii = tryparsenext_string(str, i, len, (p.delim,))

    @label done
    return R((i, ii-1)), ii

    @label error
    return R(), ii
end
# fallback to method which doesn't need options
@inline function tryparsenext(f, str, i, len, opts)
    tryparsenext(f, str, i, len)
end


### Field parsing

@qtype Field{T}(
    inner::Prim{T}
  ; ignore_init_whitespace::Bool=true
  , ignore_end_whitespace::Bool=true
  , quoted::Bool=false
  , quotechar::Char='\"'
  , escapechar::Char='\\'
  , eoldelim::Bool=false
  , spacedelim::Bool=false
  , delim::Char=','
)

fieldtype{T}(::Field{T}) = T

function tryparsenext{T}(f::Field{T}, str, i, len)
    R = Nullable{T}
    i > len && @goto error
    if f.ignore_init_whitespace
        while i <= len
            @inbounds c, ii = next(str, i)
            !iswhitespace(c) && break
            i = ii
        end
    end
    @chk2 res, i = tryparsenext(f.inner, str, i, len)

    i0 = i
    if f.ignore_end_whitespace
        while i <= len
            @inbounds c, ii = next(str, i)
            !iswhitespace(c) && break
            i = ii
        end
    end

    f.spacedelim && i > i0 && @goto done
    f.delim == '\t' && c == '\t' && @goto done

    if i > len
        if f.eoldelim
            @goto done
        else
            @goto error
        end
    end

    @inbounds c, ii = next(str, i)

    if f.eoldelim
        if c == '\r'
            i=ii
            c, ii = next(str, i)
            if c == '\n'
                i=ii
            end
            @goto done
        elseif c == '\n'
            i=ii
            c, ii = next(str, i)
            if c == '\r'
                i=ii
            end
            @goto done
        end
        @goto error
    end

    c != f.delim && @goto error # this better be the delim!!
    i = ii

    @label done
    return R(res), i

    @label error
    return R(), i
end

