# Minimal unsafe string implementation
struct UnsafeString <: AbstractString
    ptr::Ptr{UInt8}
    len::Int
end

Base.pointer(s::UnsafeString) = s.ptr
Base.pointer(s::UnsafeString, i::Integer) = s.ptr + i - 1

# Iteration. Largely indentical to Julia 0.6's String
function Base.start(s::UnsafeString)
    if s.ptr == C_NULL
        throw(ArgumentError("pointer has been zeroed. The zeroing most likely happened because the string was moved from a process to another."))
    end
    return 1
end

Base.sizeof(s::UnsafeString) = s.len

function Base.endof(s::UnsafeString)
    p = pointer(s)
    i = sizeof(s)
    while i > 0 && Base.is_valid_continuation(unsafe_load(p, i))
        i -= 1
    end
    i
end

@inline function Base.next(s::UnsafeString, i::Int)
    # function is split into this critical fast-path
    # for pure ascii data, such as parsing numbers,
    # and a longer function that can handle any utf8 data
    @boundscheck if (i < 1) | (i > s.len)
        throw(BoundsError(s, i))
    end
    p = pointer(s)
    b = unsafe_load(p, i)
    if b < 0x80
        return Char(b), i + 1
    end
    return Base.slow_utf8_next(p, b, i, sizeof(s))
end




struct StringVector <: AbstractVector{UnsafeString}
    buffer::Vector{UInt8}
    offsets::Vector{UInt64}
    lengths::Vector{UInt32}
end
StringVector() = StringVector(Vector{UInt8}(0), UInt64[], UInt32[])
function StringVector(arr::AbstractArray{<:AbstractString})
    s = StringVector()
    for x in arr
        push!(s, x)
    end
    s
end

const UNDEF_OFFSET = typemax(UInt64)
function StringVector(pa::PooledArray{<:AbstractString})
    res = StringVector()
    for i in 1:length(pa)
        if pa.refs[i] != 0
            push!(res, pa.revpool[pa.refs[i]])
        else
            push!(res.offsets, UNDEF_OFFSET)
            push!(res.lengths, 0)
        end
    end
    return res
end

Base.size(a::StringVector) = (length(a.offsets),)

Base.IndexStyle(::Type{<:StringVector}) = IndexLinear()

@inline Base.@propagate_inbounds function Base.getindex(a::StringVector, i::Integer)
    offset = a.offsets[i]
    if offset == UNDEF_OFFSET
        throw(UndefRefError())
    end
    len = if length(a.lengths) == 0
        UInt32((i == length(a) ? length(a.buffer) : a.offsets[i+1]) - offset)
    else
        a.lengths[i]
    end

    UnsafeString(pointer(a.buffer) + offset, len)
end

function Base.similar(a::StringVector, ::Type{<:UnsafeString}, dims::Tuple{Int64})
    resize!(StringVector(), dims[1])
end

function Base.empty!(a::StringVector)
    empty!(a.buffer)
    empty!(a.offsets)
    empty!(a.lengths)
end

Base.copy(a::StringVector) = StringVector(copy(a.buffer), copy(a.offsets), copy(a.lengths))

@inline function Base.setindex!(arr::StringVector, val::UnsafeString, idx::Real)
    p = pointer(arr.buffer)
    if val.ptr <= p + length(arr.buffer)-1 && val.ptr >= p
        # this means we know this guy.
        arr.offsets[idx] = val.ptr - p
        arr.lengths[idx] = val.len
    else
        _setindex!(arr, val, idx)
    end
end

@inline function Base.setindex!(arr::StringVector, val, idx)
    _setindex!(arr, val, idx)
end

function _setindex!(arr::StringVector, val::AbstractString, idx)
    buffer = arr.buffer
    l = length(arr.buffer)
    resize!(buffer, l + sizeof(val))
    unsafe_copy!(pointer(buffer, l+1), pointer(val,1), sizeof(val))
    arr.lengths[idx] = sizeof(val)
    arr.offsets[idx] = l
    val
end

function _setindex!(arr::StringVector, val::Union{StringVector,AbstractVector{<:AbstractString}}, idx::AbstractVector)
    if length(val) != length(idx)
        throw(ArgumentError("length of index range must match length of right hand side."))
    end
    for (v, i) in zip(val, idx)
        _setindex!(arr, v, i)
    end
    return val
end

function Base.resize!(arr::StringVector, len)
    l = length(arr)
    resize!(arr.offsets, len)
    resize!(arr.lengths, len)
    if l < len
        arr.offsets[l+1:len] = UNDEF_OFFSET # undef
        arr.lengths[l+1:len] = 0
    end
    arr
end

function Base.push!(arr::StringVector, val::AbstractString)
    l = length(arr.buffer)
    resize!(arr.buffer, l + sizeof(val))
    unsafe_copy!(pointer(arr.buffer, l + 1), pointer(val,1), sizeof(val))
    push!(arr.offsets, l)
    push!(arr.lengths, sizeof(val))
    arr
end
