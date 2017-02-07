using WeakRefStrings

import Base: getindex, setindex!, size

immutable StrRange
    offset::Int
    length::Int
end

type SubStringArray{T,N} <: AbstractArray{WeakRefString{UInt8}, N}
    str::T
    ranges::Array{StrRange, N}
end

# allocation requires you to give the string
function SubStringArray(str, dims::Int...)
    SubStringArray(str, Array{StrRange}(dims...))
end

size(x::SubStringArray) = size(x.ranges)

function getindex(x::SubStringArray, idx...)
    r = getindex(x.ranges, idx...)
    WeakRefString{UInt8}(pointer(Vector{UInt8}(x.str))+r.offset, r.length, r.offset)
end

function Base.setindex!(x::SubStringArray, y::WeakRefString, idx...)
    if y.ptr-y.offset !== pointer(Vector{UInt8}(x.str))
        throw(ArgumentError("The substring array has a different parent"))
    end

    x.ranges[idx...] = StrRange(y.ind, y.len)
end

function Base.setindex!(x::SubStringArray, y::StrRange, idx...)
    x.ranges[idx...] = y
end

function Base.similar(x::SubStringArray, dims::Tuple)
    SubStringArray(x.str, similar(x.ranges, dims))
end

function Base.resize!(x::SubStringArray, n)
    SubStringArray(x.str, resize!(x.ranges, n))
end
