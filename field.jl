using QuickTypes

abstract AbstractToken{T}
fieldtype{T}(::AbstractToken{T}) = T
fieldtype{T}(::Type{AbstractToken{T}}) = T
fieldtype{T<:AbstractToken}(::Type{T}) = fieldtype(supertype(T))


# Numberic parsing
@qtype Numeric{T}(
    decimal::Char='.'
  , thousands::Char=','
) <: AbstractToken{T}

Numeric{N<:Number}(::Type{N}; kws...) = Numeric{N}(;kws...)
fromtype{N<:Number}(::Type{N}) = Numeric(N)

### Unsigned integers

@inline function tryparsenext{T<:Signed}(::Numeric{T}, str, i, len)
    R = Nullable{T}
    @chk2 sign, i = tryparsenext_sign(str, i, len)
    @chk2 x, i = tryparsenext_base10(T, str, i, len)

    @label done
    return R(sign*x), i

    @label error
    return R(), i
end

@inline function tryparsenext{T<:Unsigned}(::Numeric{T}, str, i, len)
    tryparsenext_base10(T,str, i, len)
end

@inline function tryparsenext{F<:AbstractFloat}(::Numeric{F}, str, i, len)
    R = Nullable{F}
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
        @chk2 exp, i = tryparsenext(Numeric(Int), str, ii, len)
        return R(sign*(x+f) * 10.0^exp), i
    end

    @label done
    return R(sign*(x+f)), i

    @label error
    return R(), i
end

using Base.Test
let
    @test tryparsenext(fromtype(Float64), "21", 1, 2) |> unwrap== (21.0,3)
    @test tryparsenext(fromtype(Float64), ".21", 1, 3) |> unwrap== (.21,4)
    @test tryparsenext(fromtype(Float64), "1.21", 1, 4) |> unwrap== (1.21,5)
    @test tryparsenext(fromtype(Float64), "-1.21", 1, 5) |> unwrap== (-1.21,6)
    @test tryparsenext(fromtype(Float64), "-1.5e-12", 1, 8) |> unwrap == (-1.5e-12,9)
    @test tryparsenext(fromtype(Float64), "-1.5E-12", 1, 8) |> unwrap == (-1.5e-12,9)
end


immutable Str{T} <: AbstractToken{T}
    endchar::Char
    escapechar::Char
    includenewline::Bool
end

Str{T}(t::Type{T}, endchar=',', escapechar='\\', includenewline=false) = Str{T}(endchar, escapechar, includenewline)
fromtype{S<:AbstractString}(::Type{S}) = Str(S)

function tryparsenext{T}(s::Str{T}, str, i, len)
    R = Nullable{T}
    i > len && return R(), i
    p = ' '
    i0 = i
    while true
        i > len && break
        c, ii = next(str, i)
        if (c == s.endchar && p != s.escapechar) ||
            (!s.includenewline && isnewline(c))
            break
        end
        i = ii
        p = c
    end

    return R(_substring(T, str, i0, i-1)), i
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

let
    for (s,till) in [("test  ",7), ("\ttest ",7), ("test\nasdf", 5), ("test,test", 5), ("test\\,test", 11)]
        @test tryparsenext(Str(String), s) |> unwrap == (s[1:till-1], till)
    end
    for (s,till) in [("test\nasdf", 10), ("te\nst,test", 6)]
        @test tryparsenext(Str(String, ',', '"', true), s) |> unwrap == (s[1:till-1], till)
    end
    @test tryparsenext(Str(String, ',', '"', true), "") |> failedat == 1
end


immutable LiteStr
    range::UnitRange{Int}
end
fromtype(::Type{LiteStr}) = Str(LiteStr)

@inline function _substring(::Type{LiteStr}, str, i, j)
    LiteStr(i:j)
end

@qtype Quoted{T, S<:AbstractToken}(
    inner::S
  ; output_type::Type{T}=fieldtype(inner)
  , required::Bool=false
  , quotechar::Char='"'
  , escapechar::Char='\\'
) <: AbstractToken{T}

function tryparsenext{T}(q::Quoted{T}, str, i, len)
    R = Nullable{T}
    i > len && @goto error
    c, ii = next(str, i)
    quotestarted = false
    if q.quotechar == c
        quotestarted = true
        i = ii
    else
        q.required && @goto error
    end
    @chk2 x, i = tryparsenext_inner(q, str, i, len, quotestarted)

    if i > len
        quotestarted && @goto error
        @goto done
    end
    c, ii = next(str, i)
    # TODO: eat up whitespaces?
    if quotestarted && c != q.quotechar
        @goto error
    end
    i = ii

    @label done
    return R(x), i

    @label error
    return R(), i
end

# XXX: feels like a hack - might be slow
@inline function tryparsenext_inner{T,S<:Str}(q::Quoted{T,S}, str, i, len, quotestarted)
    if quotestarted
        return tryparsenext(Str(T, q.quotechar, q.escapechar, true), str, i, len)
    else
        return tryparsenext(q.inner, str, i, len)
    end
end

@inline function tryparsenext_inner(q::Quoted, str, i, len, quotestarted)
    tryparsenext(q.inner, str, i, len)
end

let
    @test tryparsenext(Quoted(Str(String)), "\"abc\"") |> unwrap == ("abc", 6)
    @test tryparsenext(Quoted(Str(String)), "\"a\\\"bc\"") |> unwrap == ("a\\\"bc", 8)
    @test tryparsenext(Quoted(Str(String)), "x\"abc\"") |> unwrap == ("x\"abc\"", 7)
    @test tryparsenext(Quoted(Str(String)), "\"a\nbc\"") |> unwrap == ("a\nbc", 7)
    @test tryparsenext(Quoted(Str(String), required=true), "x\"abc\"") |> failedat == 1
end

### Nullable

const NA_Strings = ("NA", "N/A","#N/A", "#N/A N/A", "#NA",
                    "-1.#IND", "-1.#QNAN", "-NaN", "-nan",
                    "1.#IND", "1.#QNAN", "N/A", "NA",
                    "NULL", "NaN", "nan")

@qtype NAToken{T, S<:AbstractToken}(
    inner::S
  ; emptyisna=true
  , endchar=','
  , nastrings=NA_Strings
  , output_type::Type{T}=Nullable{fieldtype(inner)}
) <: AbstractToken{T}

function tryparsenext{T}(na::NAToken{T}, str, i, len)
    R = Nullable{T}
    i > len && @goto error
    c, ii=next(str,i)
    if (c == na.endchar || isnewline(c)) && na.emptyisna
       @goto null
    end

    @chk2 x,ii = tryparsenext(na.inner, str, i, len) maybe_null

    @label done
    return R(T(x)), ii

    @label maybe_null
    @chk2 nastr, ii = tryparsenext(Str(String, na.endchar, '\\', false), str, i,len)
    if nastr in na.nastrings
        i=ii
        @goto null
    end
    return R(), i

    @label null
    return R(T()), i

    @label error
    return R(), i
end

fromtype{N<:Nullable}(::Type{N}) = NAToken(fromtype(eltype(N)))

let
    @test tryparsenext(NAToken(fromtype(Float64)), ",") |> unwrap |> failedat == 1 # is nullable
    @test tryparsenext(NAToken(fromtype(Float64)), "X,") |> failedat == 1
    @test tryparsenext(NAToken(fromtype(Float64)), "NA,") |> unwrap |> failedat == 3
    @test tryparsenext(NAToken(fromtype(Float64)), "1.212,") |> unwrap |> unwrap == (1.212, 6)
end

### Field parsing

@qtype Field{T,S<:AbstractToken}(
    inner::S
  ; ignore_init_whitespace::Bool=true
  , ignore_end_whitespace::Bool=true
  , quoted::Bool=false
  , quotechar::Char='\"'
  , escapechar::Char='\\'
  , eoldelim::Bool=false
  , spacedelim::Bool=false
  , delim::Char=','
  , output_type::Type{T}=fieldtype(inner)
) <: AbstractToken{T}

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

