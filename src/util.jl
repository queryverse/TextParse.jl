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

@inline function tryparsenext_base10_digit(T,str,i, len)
    y = iterate(str,i)
    y===nothing && @goto error
    c = y[1]; ii = y[2]
    '0' <= c <= '9' || @goto error
    return convert(T, c-'0'), ii

    @label error
    return nothing
end

@inline function tryparsenext_base10(T, str,i,len)
    R = Nullable{T}
    y = tryparsenext_base10_digit(T,str,i, len)
    y===nothing && return R(), i
    r = y[1]; i = y[2]
    ten = T(10)
    while true
        y2 = tryparsenext_base10_digit(T,str,i,len)
        y2===nothing && break
        d = y2[1]; i = y2[2]
        r = r*ten + d
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

    # TODO Is this correct?
    return i-1
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
