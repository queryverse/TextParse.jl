struct StringVector <: AbstractVector{WeakRefString}
    buffer::Vector{UInt8}
    offsets::Vector{UInt32}
    lengths::Vector{UInt32}
end
StringVector() = StringVector(Vector{UInt8}(0), UInt32[], UInt32[])
function StringVector(arr::PooledArray{String})
    StringVector
end

Base.size(a::StringVector) = (length(a.offsets),)

Base.IndexStyle(::Type{<:StringVector}) = IndexLinear()

@inline Base.@propagate_inbounds function Base.getindex(a::StringVector, i::Integer)
    offset = a.offsets[i]
    if offset == -1
        throw(UndefRefError())
    end
    len = if length(a.lengths) == 0
        (i == length(a) ? length(a.buffer) : a.offsets[i+1]) - offset
    else
        a.lengths[i]
    end

    WeakRefString(pointer(a.buffer) + offset, len)
end

function Base.similar(a::StringVector, ::Type{<:WeakRefString}, dims::Tuple{Int64})
    resize!(StringVector(), dims[1])
end

function Base.empty!(a::StringVector)
    empty!(a.buffer)
    empty!(a.offsets)
    empty!(a.lengths)
end

Base.copy(a::StringVector) = StringVector(copy(a.buffer), copy(a.offsets), copy(a.lengths))

@inline function Base.setindex!(arr::StringVector, val::WeakRefString, idx)
    p = pointer(arr.buffer)
    if val.ptr <= p + length(arr.buffer)-1 && val.ptr >= p
        # this means we know this guy.
        if isempty(arr.lengths)
            fill_lengths!(arr)
        end
        arr.offsets[idx] = val.ptr - p
        arr.lengths[idx] = val.len
    else
        _setindex!(arr, val, idx)
    end
end

@inline function Base.setindex!(arr::StringVector, val, idx)
    _setindex!(arr, val, idx)
end

function fill_lengths!(arr::StringVector)
    resize!(arr.lengths, length(arr))
    offsets = arr.offsets
    # fill lengths array
    for i=1:length(offsets)-1
        arr.lengths[i] = offsets[i+1] - offsets[i]
    end
    arr.lengths[end] = length(arr.buffer) - offsets[end]
end

function _setindex!(arr::StringVector, val, idx)
    buffer = arr.buffer
    l = length(arr.buffer)
    if idx == length(arr) && isempty(arr.lengths) # set last element
        resize!(buffer, arr.offsets[idx] + endof(val))
        unsafe_copy!(pointer(buffer, l+1), _pointer(val,1), endof(val))
        arr.offsets[idx] = arr.offsets[idx-1] + endof(val)
        if !isempty(arr.lengths)
            arr.lengths[idx] = endof(val)
        end
        val
    else
        # append to buffer
        if isempty(arr.lengths)
            fill_lengths!(arr)
        end
        resize!(buffer, l + endof(val))
        unsafe_copy!(pointer(buffer, l+1), _pointer(val,1), endof(val))
        arr.lengths[idx] = endof(val)
        arr.offsets[idx] = l
        val
    end
end

function Base.resize!(arr::StringVector, len)
    l = length(arr)
    resize!(arr.buffer, len + 1)
    if !isempty(arr.lengths)
        resize!(arr.lengths, len)
    end
    if l < len
        arr.offsets[l+2:len+1] = -1 # undef
    end
    arr
end

function Base.push!(arr::StringVector, val)
    l = length(arr.buffer)
    resize!(arr.buffer, l + endof(val))
    unsafe_copy!(pointer(arr.buffer, l+1), _pointer(val,1), endof(val))
    push!(arr.offsets, l)
    if !isempty(arr.lengths)
        push!(arr.lengths, endof(val))
    end
    arr
end
