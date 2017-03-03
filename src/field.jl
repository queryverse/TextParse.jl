using QuickTypes

abstract AbstractToken{T}
fieldtype{T}(::AbstractToken{T}) = T
fieldtype{T}(::Type{AbstractToken{T}}) = T
fieldtype{T<:AbstractToken}(::Type{T}) = fieldtype(supertype(T))


## options passed down for tokens (specifically NAToken, StringToken)
## inside a Quoted token
immutable LocalOpts
    endchar::Char         # End parsing at this char
    quotechar::Char       # Quote char
    escapechar::Char      # Escape char
    includenewlines::Bool # Whether to include newlines in string parsing
end

function tryparsenext(tok::AbstractToken, str, i, len, locopts)
    tryparsenext(tok, str, i, len)
end

# needed for promoting guessses
immutable Unknown <: AbstractToken{Union{}} end
fromtype(::Type{Union{}}) = Unknown()
tryparsenext(::Unknown, str, i, j) = Nullable{Void}(nothing), i

# Numberic parsing
immutable Numeric{T} <: AbstractToken{T}
    decimal::Char
    thousands::Char
end

Numeric{T}(::Type{T}, decimal='.', thousands=',') = Numeric{T}(decimal, thousands)
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
    @chk2 y, i = tryparsenext_base10(Int, str, ii, len) done
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

immutable StringToken{T} <: AbstractToken{T}
    endchar::Char
    escapechar::Char
    includenewlines::Bool
end

StringToken{T}(t::Type{T}, endchar=',', escapechar='\\', includenewlines=false) = StringToken{T}(endchar, escapechar, includenewlines)
fromtype{S<:AbstractString}(::Type{S}) = StringToken(S)

function tryparsenext{T}(s::StringToken{T}, str, i, len,
                         opts=LocalOpts(s.endchar, '"', s.escapechar, s.includenewlines))
    R = Nullable{T}
    i > len && return R(), i
    p = ' '
    i0 = i
    while true
        i > len && break
        c, ii = next(str, i)
        if (c == opts.endchar && p != opts.escapechar) ||
            (!opts.includenewlines && isnewline(c))
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

if VERSION <= v"0.6.0-dev"
    # from lib/Str.jl
    @inline function _substring(::Type{Str}, str, i, j)
        Str(pointer(Vector{UInt8}(str))+(i-1), j-i+1)
    end
end

@inline function _substring{T<:SubString}(::Type{T}, str, i, j)
    T(str, i, j)
end

# using WeakRefStrings
# @inline function _substring{T<:WeakRefString}(::Type{T}, str, i, j)
#     vec = Vector{UInt8}(str)
#     WeakRefString(pointer(vec)+(i-1), (j-i+1))
# end
fromtype(::Type{StrRange}) = StringToken(StrRange)

@inline function alloc_string(str, r::StrRange)
    unsafe_string(pointer(str, 1+r.offset), r.length)
end

@inline function _substring(::Type{StrRange}, str, i, j)
    StrRange(i-1, j-i+1)
end

@inline function _substring(::Type{WeakRefString}, str, i, j)
    WeakRefString(pointer(str, i), j-i+1)
end

@qtype Quoted{T, S<:AbstractToken}(
    inner::S
  ; output_type::Type{T}=fieldtype(inner)
  , required::Bool=false
  , includenewlines::Bool=true
  , quotechar::Char='"'
  , escapechar::Char='\\'
) <: AbstractToken{T}

function tryparsenext{T}(q::Quoted{T}, str, i, len)
    R = Nullable{T}
    x = R()
    if i > len
        q.required && @goto error
        # check to see if inner thing is ok with an empty field
        @chk2 x, i = tryparsenext(q.inner, str, i, len) error
        @goto done
    end
    c, ii = next(str, i)
    quotestarted = false
    if q.quotechar == c
        quotestarted = true
        i = ii
    else
        q.required && @goto error
    end

    @chk2 x, i = if quotestarted
        opts = LocalOpts(q.quotechar, q.quotechar, q.escapechar, q.includenewlines)
        tryparsenext(q.inner, str, i, len, opts)
    else
        tryparsenext(q.inner, str, i, len)
    end

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

## Date and Time
@qtype DateTimeToken{T,S<:DateFormat}(
    output_type::Type{T},
    format::S
) <: AbstractToken{T}
fromtype(df::DateFormat) = DateTimeToken(DateTime, df)
fromtype(::Type{DateTime}) = DateTimeToken(DateTime, ISODateTimeFormat)
fromtype(::Type{Date}) = DateTimeToken(Date, ISODateFormat)

function fromtype(nd::Nullable{DateFormat})
    if !isnull(nd)
        NAToken(DateTimeToken(DateTime, get(nd)))
    else
        fromtype(Nullable{DateTime})
    end
end

function tryparsenext{T}(dt::DateTimeToken{T}, str, i, len)
    R = Nullable{T}
    nt, i = tryparse_internal(T, str, dt.format, i, len)
    if isnull(nt)
        return R(), i
    else
        return R(T(unsafe_get(nt)...)), i
    end
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

function tryparsenext{T}(na::NAToken{T}, str, i, len,
                         opts=LocalOpts(na.endchar,'"','\\',false))
    R = Nullable{T}
    if i > len
        if na.emptyisna
            @goto null
        else
            @goto error
        end
    end

    c, ii=next(str,i)
    #@show na.endchar
    if (c == opts.endchar || isnewline(c)) && na.emptyisna
       @goto null
    end

    @chk2 x,ii = tryparsenext(na.inner, str, i, len) maybe_null

    @label done
    return R(T(x)), ii

    @label maybe_null
    @chk2 nastr, ii = tryparsenext(StringToken(WeakRefString, opts.endchar, opts.escapechar, opts.includenewlines), str, i,len)
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

### Field parsing

abstract AbstractField{T} <: AbstractToken{T} # A rocord is a collection of abstract fields

@qtype Field{T,S<:AbstractToken}(
    inner::S
  ; ignore_init_whitespace::Bool=true
  , ignore_end_whitespace::Bool=true
  , eoldelim::Bool=false
  , spacedelim::Bool=false
  , delim::Char=','
  , output_type::Type{T}=fieldtype(inner)
) <: AbstractField{T}

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

    if f.ignore_end_whitespace
        i0 = i
        while i <= len
            @inbounds c, ii = next(str, i)
            !iswhitespace(c) && break
            i = ii
            f.delim == '\t' && c == '\t' && @goto done
        end

        f.spacedelim && i > i0 && @goto done
    end

    if i > len
        if f.eoldelim
            @goto done
        else
            @goto error
        end
    end

    @inbounds c, ii = next(str, i)
    f.delim == c && (i=ii; @goto done)
    f.spacedelim && iswhitespace(c) && (i=ii; @goto done)

    if f.eoldelim
        if c == '\r'
            i=ii
            if i <= len
                @inbounds c, ii = next(str, i)
                if c == '\n'
                    i=ii
                end
            end
            @goto done
        elseif c == '\n'
            i=ii
            if i <= len
                @inbounds c, ii = next(str, i)
                if c == '\r'
                    i=ii
                end
            end
            @goto done
        end
    end

    @label error
    return R(), i

    @label done
    return R(res), i
end

