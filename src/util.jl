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
        if x[1] === nothing
            $(esc(:(@goto $label)))
        else
            $(esc(res)) = something(x[1])
        end
    end
end

@inline function tryparsenext_base10_digit(T,str,i, len)
    R = Some{T}
    i > len && @goto error
    @inbounds c,ii = iterate(str,i)
    '0' <= c <= '9' || @goto error
    return R(convert(T, c-'0')), ii

    @label error
    return nothing, i
end

@inline function tryparsenext_base10(T, str,i,len)
    R = Some{T}
    @chk2 r, i = tryparsenext_base10_digit(T,str,i, len)
    ten = T(10)
    while true
        @chk2 d, i = tryparsenext_base10_digit(T,str,i,len) done
        r = r*ten + d
    end
    @label done
    return R(convert(T, r)), i

    @label error
    return nothing, i
end

@inline function tryparsenext_sign(str, i, len)
    R = Some{Int}
    i > len && return nothing, i
    c, ii = iterate(str, i)
    if c == '-'
        return R(-1), ii
    elseif c == '+'
        return R(1), ii
    else
        return (R(1), i)
    end
end

@inline function isspace(c::Char)
    c == ' '
end

@inline function isnewline(c::Char)
    c == '\n' || c == '\r'
end

@inline function eatwhitespaces(str, i=1, l=lastindex(str))
    while i <= l
        c, ii = iterate(str, i)
        if isspace(c)
            i=ii
        else
            break
        end
    end
    return i
end


function eatnewlines(str, i=1, l=lastindex(str))
    count = 0
    while i<=l
        c, ii = iterate(str, i)
        if c == '\r'
            i=ii
            if i <= l
                @inbounds c, ii = iterate(str, i)
                if c == '\n'
                    i=ii
                end
            end
            count += 1
        elseif c == '\n'
            i=ii
            if i <= l
                @inbounds c, ii = iterate(str, i)
                if c == '\r'
                    i=ii
                end
            end
            count += 1
        else
            break
        end
    end

    return i, count
end

# Move past consecutive lines that start with commentchar.
# Return a tuple of the new pos in str and the amount of comment lines moved past.
function eatcommentlines(str, i=1, l=lastindex(str), commentchar::Union{Char, Nothing}=nothing) 
    commentchar == nothing && return i, 0

    count = 0
    while i <= l && str[i] == commentchar
        i = getlineend(str, i)
        _, i = iterate(str, i)
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
    while i<=l
        c, ii = iterate(str, i)
        isnewline(c) && break
        i = ii
    end

    return i-1
end

### Testing helpers

unwrap(xs) = (something(xs[1]), xs[2:end]...)
failedat(xs) = (@assert xs[1] === nothing; xs[2])

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

    c, ii = iterate(str, line_start)
    line_end = line_start
    while !isnewline(c) && ii <= l
        line_end = ii
        c, ii = iterate(str, ii)
    end

    line_start:line_end
end

_widen(::Type{UInt8}) = UInt16 # fix for bad Base behavior
_widen(::Type{Int8}) = Int16
_widen(T) = widen(T)
