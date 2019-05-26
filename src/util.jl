### Parsing utilities

include("lib/result.jl")

#=
A relic from the past

macro chk1(expr,label=:error)
    quote
        x = $(esc(expr))
        if isnull(x[1])
            @goto $label
        else
           x[1].value, x[2]
        end
    end
end
=#

macro chk2(expr,label=:error)
    @assert expr.head == :(=)
    lhs, rhs = expr.args

    @assert lhs.head == :tuple
    res, state = lhs.args
    quote
        x = $(esc(rhs))
        $(esc(state)) = x[2] # bubble error location
        if isnull(x[1])
            $(esc(:(@goto $label)))
        else
            $(esc(res)) = x[1].value
        end
    end
end

@inline _isdigit(c::Char) = isdigit(c)

@inline function parse_uint_and_stop(str, i, len, n::T) where {T <: Integer}
    ten = T(10)
    # specialize handling of the first digit so we can return an error
    max_without_overflow = div(typemax(T)-9,10) # the larg
    y1 = iterate(str, i)
    y1===nothing && return n, false, i
    c = y1[1]
    if _isdigit(c) && n <= max_without_overflow
        n *= ten
        n += T(c-'0')
    else
        return n, false, i
    end
    i = y1[2]

    y2 = iterate(str, i)
    while y2!==nothing && n <= max_without_overflow
        c = y2[1]
        if _isdigit(c)
            n *= ten
            n += T(c-'0')
        else
            return n, true, i
        end
        i = y2[2]

        y2 = iterate(str, i)
    end
    return n, true, i
end

# slurp up extra digits
@inline function read_digits(str, i, len)
    y = iterate(str, i)
    while y!==nothing
        c = y[1]
        if !_isdigit(c) # do nothing
            return i
        end
        i = y[2]
        y = iterate(str, i)
    end
    return i
end

@inline function tryparsenext_base10_digit(T,str,i, len)
    y = iterate(str,i)
    y===nothing && @goto error
    c = y[1]; ii = y[2]
    '0' <= c <= '9' || @goto error
    return convert(T, c-'0'), ii

    @label error
    return nothing
end

Base.@pure maxdigits(::Type{T}) where {T} = ndigits(typemax(T))
Base.@pure min_with_max_digits(::Type{T}) where {T} = convert(T, T(10)^(maxdigits(T)-1))

@inline function tryparsenext_base10(T, str,i,len)
    i0 = i
    R = Nullable{T}
    y = tryparsenext_base10_digit(T,str,i, len)
    y===nothing && return R(), i
    r = y[1]; i = y[2]

    # Eat zeros
    while r==0
        y2 = tryparsenext_base10_digit(T,str,i, len)
        y2 === nothing && return R(convert(T, 0)), i
        r = y2[1]; i = y2[2]
    end

    digits = 1
    ten = T(10)
    while true
        y2 = tryparsenext_base10_digit(T,str,i,len)
        y2===nothing && break
        digits += 1
        d = y2[1]; i = y2[2]
        r = r*ten + d
    end

    max_digits = maxdigits(T)

    # Checking for overflow
    if digits > max_digits
        # More digits than the max value we can hold, this is certainly
        # an overflow
        return R(), i0
    elseif digits == max_digits && r < min_with_max_digits(T)
        # Same digits as the max digits we can hold. If the number we computed
        # is now smaller than the smallest number with the same number of
        # digits as the typemax number, we must have overflown, so we
        # again return a parsing failure
        return R(), i0
    end

    return R(convert(T, r)), i
end

@inline function tryparsenext_sign(str, i, len)
    R = Nullable{Int}

    y = iterate(str, i)
    if y===nothing
        return return R(), i
    else
        c = y[1]; ii = y[2]
        if c == '-'
            return R(-1), ii
        elseif c == '+'
            return R(1), ii
        else
            return R(1), i
        end
    end
end

@inline function isspace(c::Char)
    c == ' '
end

@inline function isnewline(c::Char)
    c == '\n' || c == '\r'
end

@inline function eatwhitespaces(str, i=1, l=lastindex(str))
    y = iterate(str, i)
    while y!==nothing
        c = y[1]; ii = y[2]
        if isspace(c)
            i=ii
        else
            break
        end
        y = iterate(str, i)
    end
    return i
end


function eatnewlines(str, i=1, l=lastindex(str))
    count = 0
    y = iterate(str, i)
    while y!==nothing
        c = y[1]; ii = y[2]
        if c == '\r'
            i=ii
            y2 = iterate(str, i)
            if y2!==nothing
                c = y2[1]
                ii = y2[2]
                if c == '\n'
                    i=ii
                end
            end
            count += 1
        elseif c == '\n'
            i=ii
            y3 = iterate(str, i)
            if y3!==nothing
                c = y3[1]
                ii = y3[2]
                if c == '\r'
                    i=ii
                end
            end
            count += 1
        else
            break
        end
        y = iterate(str, i)
    end

    return i, count
end

# Move past consecutive lines that start with commentchar.
# Return a tuple of the new pos in str and the amount of comment lines moved past.
function eatcommentlines(str, i=1, l=lastindex(str), commentchar::Union{Char, Nothing}=nothing) 
    commentchar === nothing && return i, 0

    count = 0
    while i <= l && str[i] == commentchar
        i = getlineend(str, i)
        y = iterate(str, i)
        y === nothing && return i, count
        i = y[2]
        i, lines = eatnewlines(str, i)
        count += lines
    end
    return i, count
end

function stripquotes(x)
    x[1] in ('\'', '"') && x[1] == x[end] ?
        strip(x, x[1]) : x
end

function getlineend(str, i=1, l=lastindex(str))
    y = iterate(str, i)
    while y!==nothing
        c = y[1]; ii = y[2]
        isnewline(c) && break
        i = ii
        y = iterate(str, i)
    end

    return prevind(str, i)
end

# This is similar to getlineend, but ignores line ends inside
# quotes
function getrowend(str, i, len, opts, delim)
    i0 = i
    i = eatwhitespaces(str, i, len)
    y = iterate(str, i)
    while y!==nothing
        c = y[1]; i = y[2]
        if c==Char(opts.quotechar)
            # We are now inside a quoted field
            y2 = iterate(str, i)
            while y2!==nothing
                c = y2[1]; i = y2[2]
                if c==Char(opts.escapechar)
                    y3 = iterate(str, i)
                    if y3===nothing
                        if c==Char(opts.quotechar)
                            return prevind(str, i)
                        else
                            error("Parsing error, quoted string never terminated.")
                        end
                    else
                        c2 = y3[1]; ii = y3[2]
                        if c2==Char(opts.quotechar)
                            i = ii
                        elseif c==Char(opts.quotechar)
                            break
                        end
                    end
                elseif c==Char(opts.quotechar)
                    break;
                end
                y2 = iterate(str, i)
                if y2===nothing
                    error("Parsing error, quoted string never terminated.")
                end
            end
            i = eatwhitespaces(str, i, len)
            y4 = iterate(str, i)
            if y4!==nothing
                c = y4[1]; i4 = y4[2]
                if isnewline(c)
                    return prevind(str, i)
                elseif c!=Char(delim)
                    error("Invalid line")
                end
            else
                return prevind(str, i)
            end
        else
            # We are now inside a non quoted field
            while y!==nothing
                c = y[1]; i = y[2]
                if c==Char(delim)
                    i = eatwhitespaces(str, i)
                    break
                elseif isnewline(c)
                    return prevind(str, i, 2)
                end
                y = iterate(str, i)
            end
        end
        y = iterate(str, i)
    end
    return prevind(str, i)
end

### Testing helpers

unwrap(xs) = (get(xs[1]), xs[2:end]...)
failedat(xs) = (@assert isnull(xs[1]); xs[2])

# String speedup hacks

# StrRange
# This type is the beginning of a hack to avoid allocating 3 objects
# instead of just 1 when using the `tryparsenext` framework.
# The expression (Some{String}("xyz"), 4) asks the GC to track
# the string, the nullable and the tuple. Instead we return
# (Some{StrRange}(StrRange(0,3)), 4) which makes 0 allocations.
# later when assigning the column inside `tryparsesetindex` we
# create the string. See `setcell!`
struct StrRange
    offset::Int
    length::Int
    escapecount::Int
end

function getlineat(str, i)
    l = lastindex(str)
    if i <= l
        ii = prevind(str, i)
    else
        ii = l
    end
    line_start = i
    while ii > 0 && !isnewline(str[ii])
        line_start = ii
        ii = prevind(str, line_start)
    end

    # TODO Handle nothing case
    c, ii = iterate(str, line_start)
    line_end = line_start
    while !isnewline(c) && ii <= l
        line_end = ii
        # TODO Handle nothing case
        c, ii = iterate(str, ii)
    end

    line_start:line_end
end

_widen(::Type{UInt8}) = UInt16 # fix for bad Base behavior
_widen(::Type{Int8}) = Int16
_widen(T) = widen(T)
