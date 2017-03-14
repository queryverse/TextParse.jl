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
    includequotes::Bool   # Whether to include quotes in string parsing
    includenewlines::Bool # Whether to include newlines in string parsing
end

const default_opts = LocalOpts(',', '"', '\\', false, false)
# helper function for easy testing:
@inline function tryparsenext(tok::AbstractToken, str, opts::LocalOpts=default_opts)
    tryparsenext(tok, str, start(str), endof(str), opts)
end

# fallback for tryparsenext methods which don't care about local opts
@inline function tryparsenext(tok::AbstractToken, str, i, len, locopts)
    tryparsenext(tok, str, i, len)
end


# needed for promoting guessses
immutable Unknown <: AbstractToken{Union{}} end
fromtype(::Type{Union{}}) = Unknown()
function tryparsenext(::Unknown, str, i, len, opts)
    Nullable{Void}(nothing), i
end

# Numberic parsing
immutable Numeric{T} <: AbstractToken{T}
    decimal::Char
    thousands::Char
end

Numeric{T}(::Type{T}, decimal='.', thousands=',') = Numeric{T}(decimal, thousands)
fromtype{N<:Number}(::Type{N}) = Numeric(N)

### Unsigned integers

function tryparsenext{T<:Signed}(::Numeric{T}, str, i, len)
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
end

function StringToken{T}(t::Type{T})
    StringToken{T}()
end

fromtype{S<:AbstractString}(::Type{S}) = StringToken(S)

function tryparsenext{T}(s::StringToken{T}, str, i, len, opts)
    R = Nullable{T}
    p = ' '
    i0 = i
    if opts.includequotes && i <= len
        c, ii = next(str, i)
        if c == opts.quotechar
            i = ii # advance counter so that
                   # the while loop doesn't react to opening quote
        end
    end

    while i <= len
        c, ii = next(str, i)
        if c == opts.endchar
            if opts.endchar == opts.quotechar
                # this means we're inside a quoted string
                if opts.quotechar == opts.escapechar
                    # sometimes the quotechar is the escapechar
                    # in that case we need to see the next char
                    if ii > len
                        if opts.includequotes
                            i=ii
                        end
                        break
                    end
                    nxt, j = next(str, ii)
                    if nxt == opts.quotechar
                        # the current character is escaping the
                        # next one
                        i = j # skip next char as well
                        p = nxt
                        continue
                    end
                elseif p == opts.escapechar
                    # previous char escaped this one
                    i = ii
                    p = c
                    continue
                end
            end
            if opts.includequotes
                i = ii
            end
            break
        elseif (!opts.includenewlines && isnewline(c))
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

export Quoted

immutable Quoted{T, S<:AbstractToken} <: AbstractToken{T}
    inner::S
    required::Bool
    includequotes::Bool
    includenewlines::Bool
    quotechar::Nullable{Char}
    escapechar::Nullable{Char}
end

function Quoted{S<:AbstractToken}(inner::S;
    required=false,
    includequotes=false,
    includenewlines=true,
    quotechar=Nullable{Char}(),   # This is to allow file-wide config
    escapechar=Nullable{Char}())

    T = fieldtype(S)
    Quoted{T,S}(inner, required, includequotes,
                includenewlines, quotechar, escapechar)
end

@inline quotechar(q::Quoted, opts) = get(q.quotechar, opts.quotechar)
@inline escapechar(q::Quoted, opts) = get(q.escapechar, opts.escapechar)

Quoted(t::Type; kwargs...) = Quoted(fromtype(t); kwargs...)

function tryparsenext{T}(q::Quoted{T}, str, i, len, opts)
    if i > len
        q.required && @goto error
        # check to see if inner thing is ok with an empty field
        @chk2 x, i = tryparsenext(q.inner, str, i, len, opts) error
        @goto done
    end
    c, ii = next(str, i)
    quotestarted = false
    if quotechar(q, opts) == c
        quotestarted = true
        if !q.includequotes
            i = ii
        end
    else
        q.required && @goto error
    end

    if quotestarted
        qopts = LocalOpts(quotechar(q, opts), quotechar(q, opts), escapechar(q, opts),
                         q.includequotes, q.includenewlines)
        @chk2 x, i = tryparsenext(q.inner, str, i, len, qopts)
    else
        @chk2 x, i = tryparsenext(q.inner, str, i, len, opts)
    end

    if i > len
        if quotestarted && !q.includequotes
            @goto error
        end
        @goto done
    end
    c, ii = next(str, i)
    # TODO: eat up whitespaces?
    if quotestarted && !q.includequotes
        c != quotechar(q, opts) && @goto error
        i = ii
    end


    @label done
    return Nullable{T}(x), i

    @label error
    return Nullable{T}(), i
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

function tryparsenext{T}(dt::DateTimeToken{T}, str, i, len, opts)
    R = Nullable{T}
    nt, i = tryparse_internal(T, str, dt.format, i, len, opts.endchar)
    if isnull(nt)
        return R(), i
    else
        return R(T(unsafe_get(nt)...)), i
    end
end

### Nullable

const nastrings_upcase = ["NA", "NULL", "N/A","#N/A", "#N/A N/A", "#NA",
                          "-1.#IND", "-1.#QNAN", "-NaN", "-nan",
                          "1.#IND", "1.#QNAN", "N/A", "NA", "NaN", "nan"]

const NA_STRINGS = sort!(vcat(nastrings_upcase, map(lowercase, nastrings_upcase)))

immutable NAToken{T, S<:AbstractToken} <: AbstractToken{T}
    inner::S
    emptyisna::Bool
    endchar::Nullable{Char}
    nastrings::Vector{String}
end

function NAToken{S}(
    inner::S,
  ; emptyisna=true
  , endchar=Nullable{Char}()
  , nastrings=NA_STRINGS)

    T = fieldtype(inner)
    NAToken{Nullable{T}, S}(inner, emptyisna, endchar, nastrings)
end

endchar(na::NAToken, opts) = get(na.endchar, opts.endchar)

function tryparsenext{T}(na::NAToken{T}, str, i, len, opts)
    R = Nullable{T}
    i = eatwhitespaces(str, i)
    if i > len
        if na.emptyisna
            @goto null
        else
            @goto error
        end
    end

    c, ii=next(str,i)
    if (c == endchar(na, opts) || isnewline(c)) && na.emptyisna
       @goto null
    end

    if isa(na.inner, Unknown)
        @goto maybe_null
    end
    @chk2 x,ii = tryparsenext(na.inner, str, i, len) maybe_null

    @label done
    return R(T(x)), ii

    @label maybe_null
    naopts = LocalOpts(endchar(na,opts), opts.quotechar,
                       opts.escapechar, false, opts.includenewlines)
    @chk2 nastr, ii = tryparsenext(StringToken(WeakRefString), str, i, len, naopts)
    if !isempty(searchsorted(na.nastrings, nastr))
        i=ii
        i = eatwhitespaces(str, i)
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

type Field{T,S<:AbstractToken} <: AbstractField{T}
    inner::S
    ignore_init_whitespace::Bool
    ignore_end_whitespace::Bool
    eoldelim::Bool
    spacedelim::Bool
    delim::Nullable{Char}
end

function Field{S}(inner::S; ignore_init_whitespace=true, ignore_end_whitespace=true,
               eoldelim=false, spacedelim=false, delim=Nullable{Char}(),
               output_type=fieldtype(inner))
    T = fieldtype(inner)
    Field{T,S}(inner, ignore_init_whitespace, ignore_end_whitespace,
               eoldelim, spacedelim, delim)
end

@inline delim(f::Field, opts) = get(f.delim, opts.endchar)

function swapinner(f::Field, inner::AbstractToken)
    Field(inner;
        ignore_init_whitespace= f.ignore_end_whitespace
      , ignore_end_whitespace=f.ignore_end_whitespace
      , eoldelim=f.eoldelim
      , spacedelim=f.spacedelim
      , delim=f.delim
     )

end
function tryparsenext{T}(f::Field{T}, str, i, len, opts)
    R = Nullable{T}
    i > len && @goto error
    if f.ignore_init_whitespace
        while i <= len
            @inbounds c, ii = next(str, i)
            !iswhitespace(c) && break
            i = ii
        end
    end
    @chk2 res, i = tryparsenext(f.inner, str, i, len, opts)

    if f.ignore_end_whitespace
        i0 = i
        while i <= len
            @inbounds c, ii = next(str, i)
            !iswhitespace(c) && break
            i = ii
            delim(f, opts) == '\t' && c == '\t' && @goto done
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
    delim(f, opts) == c && (i=ii; @goto done)
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

