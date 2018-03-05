struct StringVector <: AbstractVector{WeakRefString}
    buffer::Vector{UInt8}
    offsets::Vector{UInt32}
end
StringVector() = StringVector(Vector{UInt8}(0), UInt32[0])

Base.size(a::StringVector) = (length(a.offsets) - 1,)

Base.IndexStyle(::Type{<:StringVector}) = IndexLinear()

@inline Base.@propagate_inbounds function Base.getindex(a::StringVector, i::Integer)
    offset = a.offsets[i]
    len    = a.offsets[i + 1] - offset
    WeakRefString(pointer(a.buffer) + offset, len)
end

Base.similar(a::StringVector, ::Type{T}, dims::Tuple{Vararg{Int64,N}}) where {T,N} =
    throw(ArgumentError("similar shouldn't be used for StringVectors"))

Base.copy(a::StringVector) = StringVector(copy(a.buffer), copy(a.offsets))
