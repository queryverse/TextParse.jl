struct MyStringType <: AbstractString
    buffer::Vector{UInt8}
end

Base.:(==)(x::MyStringType, y::MyStringType) = x.buffer == y.buffer

Base.:(==)(x::String, y::MyStringType) = error("Not yet implemented.")
Base.:(==)(y::MyStringType, x::String) = x == y

function Base.hash(s::MyStringType, h::UInt)
    error("Not yet implemented.")
end

function Base.show(io::IO, x::MyStringType)
    print(io, '"')
    print(io, string(x))
    print(io, '"')
    return
end
# Base.print(io::IO, s::MyStringType) = print(io, string(s))
# Base.textwidth(s::MyStringType) = textwidth(string(s))

# chompnull(x::WeakRefString{T}) where {T} = unsafe_load(x.ptr, x.len) == T(0) ? x.len - 1 : x.len

# Base.string(x::WeakRefString) = x == NULLSTRING ? "" : unsafe_string(x.ptr, x.len)
# Base.string(x::WeakRefString{UInt16}) = x == NULLSTRING16 ? "" : String(transcode(UInt8, unsafe_wrap(Array, x.ptr, chompnull(x))))
# Base.string(x::WeakRefString{UInt32}) = x == NULLSTRING32 ? "" : String(transcode(UInt8, unsafe_wrap(Array, x.ptr, chompnull(x))))

# Base.convert(::Type{WeakRefString{UInt8}}, x::String) = WeakRefString(pointer(x), sizeof(x))
# Base.convert(::Type{String}, x::WeakRefString) = convert(String, string(x))
# Base.String(x::WeakRefString) = string(x)
# Base.Symbol(x::WeakRefString{UInt8}) = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), x.ptr, x.len)

Base.pointer(s::MyStringType) = pointer(s.buffer)
Base.pointer(s::MyStringType, i::Integer) = pointer(s.buffer) + i - 1

@inline Base.ncodeunits(s::MyStringType) = length(s.buffer)
Base.codeunit(s::MyStringType) = UInt8

@inline function Base.codeunit(s::MyStringType, i::Integer)
    @boundscheck checkbounds(s.buffer, i)
    return @inbounds s.buffer[i]
end

Base.thisind(s::MyStringType, i::Int) = Base._thisind_str(s, i)
# Base.nextind(s::WeakRefString, i::Int) = Base._nextind_str(s, i)
Base.isvalid(s::MyStringType, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i

Base.@propagate_inbounds function Base.iterate(s::MyStringType, i::Int=firstindex(s))
    i > ncodeunits(s) && return nothing
    b = codeunit(s, i)
    u = UInt32(b) << 24
    Base.between(b, 0x80, 0xf7) || return reinterpret(Char, u), i+1
    return Base.next_continued(s, i, u)
end

function Base.next_continued(s::MyStringType, i::Int, u::UInt32)
    u < 0xc0000000 && (i += 1; @goto ret)
    n = ncodeunits(s)
    # first continuation byte
    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16
    # second continuation byte
    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8
    # third continuation byte
    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b); i += 1
@label ret
    return reinterpret(Char, u), i
end