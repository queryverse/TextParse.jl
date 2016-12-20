import Base: getindex, setindex!, size
immutable StrRange
    range::UnitRange{Int}
end

type SubStringArray{T,N} <: AbstractArray{SubString{T}, N}
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
    SubString(x.str, first(r.range), last(r.range))
end

function setindex!(x::SubStringArray, y::StrRange, idx...)
    x.ranges[idx...] = y
    x
end
