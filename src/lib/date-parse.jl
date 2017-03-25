# This file is a part of Julia. License is MIT: http://julialang.org/license

### Parsing utilities

_directives{S,T}(::Type{DateFormat{S,T}}) = T.parameters

character_codes{S,T}(df::Type{DateFormat{S,T}}) = character_codes(_directives(df))
function character_codes(directives::SimpleVector)
    letters = sizehint!(Char[], length(directives))
    for (i, directive) in enumerate(directives)
        if directive <: DatePart
            letter = first(directive.parameters)
            push!(letters, letter)
        end
    end
    return letters
end

genvar(t::DataType) = Symbol(lowercase(string(datatype_name(t))))

include("date-tryparse-internal.jl")
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

function Base.parse{T<:TimeType}(
    ::Type{T}, str::AbstractString, df::DateFormat=default_format(T),
)
    pos, len = start(str), endof(str)
    values, pos = tryparsenext_internal(T, str, pos, len, df, true)
    T(unsafe_get(values)...)
end

function Base.tryparse{T<:TimeType}(
    ::Type{T}, str::AbstractString, df::DateFormat=default_format(T),
)
    pos, len = start(str), endof(str)
    values, pos = tryparsenext_internal(T, str, pos, len, df, false)
    if isnull(values)
        Nullable{T}()
    else
        Nullable{T}(T(unsafe_get(values)...))
    end
end

"""
    parse_components(str::AbstractString, df::DateFormat) -> Array{Any}

Parse the string into its components according to the directives in the DateFormat.
Each component will be a distinct type, typically a subtype of Period. The order of the
components will match the order of the `DatePart` directives within the DateFormat. The
number of components may be less than the total number of `DatePart`.
"""
@generated function parse_components(str::AbstractString, df::DateFormat)
    letters = character_codes(df)
    tokens = Type[CONVERSION_SPECIFIERS[letter] for letter in letters]

    quote
        pos, len = start(str), endof(str)
        values, pos, num_parsed = tryparsenext_core(str, pos, len, df, true)
        t = unsafe_get(values)
        types = $(Expr(:tuple, tokens...))
        result = Vector{Any}(num_parsed)
        for (i, typ) in enumerate(types)
            i > num_parsed && break
            result[i] = typ(t[i])  # Constructing types takes most of the time
        end
        return result
    end
end
