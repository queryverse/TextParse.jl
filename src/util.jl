### Parsing utilities

include("lib/result.jl")

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

macro chk2(expr,label=:error)
    @assert expr.head == :(=)
    lhs, rhs = expr.args

    @assert lhs.head == :tuple
    res, state = lhs.args
    quote
        x = $(esc(rhs))
        $(esc(state)) = x[2] # bubble error location
        if isnull(x[1])
            @goto $label
        else
            $(esc(res)) = x[1].value
        end
    end
end

@inline function tryparsenext_base10_digit(T,str,i, len)
    R = Nullable{T}
    i > len && @goto error
    @inbounds c,ii = next(str,i)
    '0' <= c <= '9' || @goto error
    return R(c-'0'), ii

    @label error
    return R(), i
end

@inline function tryparsenext_base10(T, str,i,len)
    R = Nullable{T}
    @chk2 r, i = tryparsenext_base10_digit(T,str,i, len)
    ten = T(10)
    while true
        @chk2 d, i = tryparsenext_base10_digit(T,str,i,len) done
        r = r*ten + d
    end
    @label done
    return R(r), i

    @label error
    return R(), i
end

@inline function tryparsenext_sign(str, i, len)
    R = Nullable{Int}
    i > len && return R(), i
    c, ii = next(str, i)
    if c == '-'
        return R(-1), ii
    elseif c == '+'
        return R(1), ii
    else
        return (R(1), i)
    end
end

@inline function iswhitespace(c::Char)
    c == ' ' || c == '\t'
end

@inline function isnewline(c::Char)
    c == '\n' || c == '\r'
end


function eatnewlines(str, i=1, l=endof(str))
    while i<=l
        c, ii = next(str, i)
        !isnewline(c) && break
        i = ii
    end

    return i
end

function getlineend(str, i=1, l=endof(str))
    while i<=l
        c, ii = next(str, i)
        isnewline(c) && break
        i = ii
    end

    return i-1
end

### Testing helpers

unwrap(xs) = (get(xs[1]), xs[2:end]...)
failedat(xs) = (@assert isnull(xs[1]); xs[2])
tryparsenext(tok, str) = tryparsenext(tok, str, 1, endof(str))

# String speedup hacks

# StrRange
# This type is the beginning of a hack to avoid allocating 3 objects
# instead of just 1 when using the `tryparsenext` framework.
# The expression (Nullable{String}("xyz"), 4) asks the GC to track
# the string, the nullable and the tuple. Instead we return
# (Nullable{StrRange}(StrRange(0,3)), 4) which makes 0 allocations.
# later when assigning the column inside `tryparsesetindex` we
# create the string. See `setcell!`
immutable StrRange
    offset::Int
    length::Int
end


# PooledArrays for string data
using WeakRefStrings
using PooledArrays

@inline function nonallocating_setindex!{T}(pa::PooledArray{T}, i, rng::StrRange, str::AbstractString)
    wstr = WeakRefString(pointer(str, 1+rng.offset), rng.length)
    pool_idx = findfirst(pa.pool, wstr)
    if pool_idx <= 0
        # allocate only here.
        val = convert(T,alloc_string(str, rng))
        pool_idx = push_pool!(pa, val)
    end

    pa.refs[i] = pool_idx
end

function push_pool!{T,R}(pa::PooledArray{T,R}, val)
    # TODO: move this refactoring to PooledArrays
    push!(pa.pool, val)
    pool_idx = length(pa.pool)
    if pool_idx > typemax(R)
        throw(ErrorException(
            "You're using a PooledArray with ref type $R, which can only hold $(int(typemax(R))) values,\n",
            "and you just tried to add the $(typemax(R)+1)th reference.  Please change the ref type\n",
            "to a larger int type, or use the default ref type ($DEFAULT_POOLED_REF_TYPE)."
        ))
    end
    if pool_idx > 1 && isless(val, pa.pool[pool_idx-1])
        # maintain sorted order
        sp = sortperm(pa.pool)
        isp = invperm(sp)
        refs = pa.refs
        for i = 1:length(refs)
            # after resize we might have some 0s
            if refs[i] != 0
                @inbounds refs[i] = isp[refs[i]]
            end
        end
        pool_idx = isp[pool_idx]
        copy!(pa.pool, pa.pool[sp])
    end
    pool_idx
end
