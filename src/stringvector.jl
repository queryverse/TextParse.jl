struct StringVector <: AbstractVector{WeakRefString{UInt8}}
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
            push!(res, pa.pool[pa.refs[i]])
        else
            push!(res.offsets, UNDEF_OFFSET)
            if !isempty(res.lengths)
                push!(res.lengths, 0)
            end
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
        # @show i, length(a), length(a.buffer), a.offsets[i+1], offset
        UInt32((i == length(a) ? length(a.buffer) : a.offsets[i+1]) - offset)
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
        next_o = offsets[i+1]
        if next_o == UNDEF_OFFSET
            # fill_lengths! is being called for the first time
            # an offset is UNDEF_OFFSET means that this is the
            # last element in the array filled so far.
            next_o = UInt64(length(arr.buffer))
        end
        arr.lengths[i] = next_o - ifelse(offsets[i]==UNDEF_OFFSET, next_o, offsets[i])
    end
    if offsets[end] !== UNDEF_OFFSET
        arr.lengths[end] = length(arr.buffer) - offsets[end]
    else
        arr.lengths[end] = 0
    end
end

function _setindex!(arr::StringVector, val::AbstractString, idx::Real)
    buffer = arr.buffer
    l = length(arr.buffer)
    if idx == length(arr) && isempty(arr.lengths) # set last element
        resize!(buffer, arr.offsets[idx] + sizeof(val))
        unsafe_copy!(pointer(buffer, l+1), pointer(val,1), sizeof(val))
        arr.offsets[idx] = idx > 1 ? arr.offsets[idx-1] + sizeof(val) : sizeof(val)
        if !isempty(arr.lengths)
            arr.lengths[idx] = sizeof(val)
        end
        val
    else
        # append to buffer
        if isempty(arr.lengths)
            fill_lengths!(arr)
        end
        resize!(buffer, l + sizeof(val))
        unsafe_copy!(pointer(buffer, l+1), pointer(val,1), sizeof(val))
        arr.lengths[idx] = sizeof(val)
        arr.offsets[idx] = l
        val
    end
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
    if !isempty(arr.lengths)
        resize!(arr.lengths, len)
    end
    if l < len
        arr.offsets[l+1:len] = UNDEF_OFFSET # undef
        if !isempty(arr.lengths)
            arr.lengths[l+1:len] = 0
        end
    end
    arr
end

function Base.push!(arr::StringVector, val::AbstractString)
    l = length(arr.buffer)
    resize!(arr.buffer, l + sizeof(val))
    unsafe_copy!(pointer(arr.buffer, l + 1), pointer(val,1), sizeof(val))
    push!(arr.offsets, l)
    if !isempty(arr.lengths)
        push!(arr.lengths, sizeof(val))
    end
    arr
end
