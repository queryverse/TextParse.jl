### Parsing utilities

import Base: unsafe_get

if (!isdefined(Base, :unsafe_get))
    unsafe_get(x::Nullable) = x.value
end

include("date-tryparse-internal.jl")

function Base.tryparse{T<:TimeType}(::Type{T}, str::AbstractString, df::DateFormat)
    nt,_ = tryparse_internal(T, str, df, start(str), endof(str), false)
    if isnull(nt)
        return Nullable{T}()
    else
        return Nullable{T}(T(unsafe_get(nt)...))
    end
end

default_format(::Type{Date}) = ISODateFormat
default_format(::Type{DateTime}) = ISODateTimeFormat

function Base.parse{T<:TimeType}(::Type{T},
                                 str::AbstractString,
                                 df::DateFormat)
    nt, _ = tryparse_internal(T, str, df, start(str), endof(str), true)
    T(unsafe_get(nt)...)
end

@inline function tryparsenext_base10(str::AbstractString, i::Int, len::Int, min_width::Int=1, max_width::Int=0)
    i > len && (return Nullable{Int64}(), i)
    min_pos = min_width <= 0 ? i : i + min_width - 1
    max_pos = max_width <= 0 ? len : min(i + max_width - 1, len)
    d::Int64 = 0
    @inbounds while i <= max_pos
        c, ii = next(str, i)
        if '0' <= c <= '9'
            d = d * 10 + (c - '0')
        else
            break
        end
        i = ii
    end
    if i <= min_pos
        return Nullable{Int64}(), i
    else
        return Nullable{Int64}(d), i
    end
end

@inline function tryparsenext_word(str::AbstractString, i, len, locale, maxchars=0)
    word_start, word_end = i, 0
    max_pos = maxchars <= 0 ? len : min(chr2ind(str, ind2chr(str,i) + maxchars - 1), len)
    @inbounds while i <= max_pos
        c, ii = next(str, i)
        if isalpha(c)
            word_end = i
        else
            break
        end
        i = ii
    end
    if word_end == 0
        return Nullable{SubString}(), i
    else
        return Nullable{SubString}(SubString(str, word_start, word_end)), i
    end
end

function Base.parse(::Type{DateTime}, s::AbstractString, df::typeof(ISODateTimeFormat))
    i, end_pos = start(s), endof(s)

    dm = dd = Int64(1)
    th = tm = ts = tms = Int64(0)

    nv, i = tryparsenext_base10(s, i, end_pos, 1)
    dy = isnull(nv) ? (@goto error) : unsafe_get(nv)
    i > end_pos && @goto error

    c, i = next(s, i)
    c != '-' && @goto error
    i > end_pos && @goto done

    nv, i = tryparsenext_base10(s, i, end_pos, 1, 2)
    dm = isnull(nv) ? (@goto error) : unsafe_get(nv)
    i > end_pos && @goto done

    c, i = next(s, i)
    c != '-' && @goto error
    i > end_pos && @goto done

    nv, i = tryparsenext_base10(s, i, end_pos, 1, 2)
    dd = isnull(nv) ? (@goto error) : unsafe_get(nv)
    i > end_pos && @goto done

    c, i = next(s, i)
    c != 'T' && @goto error
    i > end_pos && @goto done

    nv, i = tryparsenext_base10(s, i, end_pos, 1, 2)
    th = isnull(nv) ? (@goto error) : unsafe_get(nv)
    i > end_pos && @goto done

    c, i = next(s, i)
    c != ':' && @goto error
    i > end_pos && @goto done

    nv, i = tryparsenext_base10(s, i, end_pos, 1, 2)
    tm = isnull(nv) ? (@goto error) : unsafe_get(nv)
    i > end_pos && @goto done

    c, i = next(s, i)
    c != ':' && @goto error
    i > end_pos && @goto done

    nv, i = tryparsenext_base10(s, i, end_pos, 1, 2)
    ts = isnull(nv) ? (@goto error) : unsafe_get(nv)
    i > end_pos && @goto done

    c, i = next(s, i)
    c != '.' && @goto error
    i > end_pos && @goto done

    nv, j = tryparsenext_base10(s, i, end_pos, 1, 3)
    tms = isnull(nv) ? (@goto error) : unsafe_get(nv)
    tms *= 10 ^ (3 - (j - i))

    j > end_pos || @goto error

    @label done
    return DateTime(dy, dm, dd, th, tm, ts, tms)

    @label error
    throw(ArgumentError("Invalid DateTime string"))
end
