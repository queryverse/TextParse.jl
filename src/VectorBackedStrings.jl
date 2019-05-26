struct VectorBackedUTF8String <: AbstractString
    buffer::Vector{UInt8}
end

Base.:(==)(x::VectorBackedUTF8String, y::VectorBackedUTF8String) = x.buffer == y.buffer

function Base.show(io::IO, x::VectorBackedUTF8String)
    print(io, '"')
    print(io, string(x))
    print(io, '"')
    return
end

Base.pointer(s::VectorBackedUTF8String) = pointer(s.buffer)

Base.pointer(s::VectorBackedUTF8String, i::Integer) = pointer(s.buffer) + i - 1

Base.pointer(s::SubString{VectorBackedUTF8String}, i::Integer) = pointer(s.string) + s.offset + i - 1

@inline Base.ncodeunits(s::VectorBackedUTF8String) = length(s.buffer)

Base.codeunit(s::VectorBackedUTF8String) = UInt8

@inline function Base.codeunit(s::VectorBackedUTF8String, i::Integer)
    @boundscheck checkbounds(s.buffer, i)
    return @inbounds s.buffer[i]
end

Base.thisind(s::VectorBackedUTF8String, i::Int) = Base._thisind_str(s, i)

Base.nextind(s::VectorBackedUTF8String, i::Int) = Base._nextind_str(s, i)

Base.isvalid(s::VectorBackedUTF8String, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i

Base.@propagate_inbounds function Base.iterate(s::VectorBackedUTF8String, i::Int=firstindex(s))
    i > ncodeunits(s) && return nothing
    b = codeunit(s, i)
    u = UInt32(b) << 24
    Base.between(b, 0x80, 0xf7) || return reinterpret(Char, u), i+1
    return our_next_continued(s, i, u)
end

function our_next_continued(s::VectorBackedUTF8String, i::Int, u::UInt32)
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

# The following functions all had implementations in WeakRefStrings (which was taken
# as a starting point for the code in this file), but aren't needed for the
# TextParse.jl use. For now we leave stubs that throw errors around. If this type
# turns out to be useful beyond TextParse.jl, these should be implemented properly.

Base.:(==)(x::String, y::VectorBackedUTF8String) = error("Not yet implemented.")

Base.:(==)(y::VectorBackedUTF8String, x::String) = x == y

Base.hash(s::VectorBackedUTF8String, h::UInt) = error("Not yet implemented.")

Base.print(io::IO, s::VectorBackedUTF8String) = error("Not yet implemented.")

Base.textwidth(s::VectorBackedUTF8String) = error("Not yet implemented.")

Base.string(x::VectorBackedUTF8String) = unsafe_string(pointer(x.buffer), length(x.buffer))

Base.convert(::Type{VectorBackedUTF8String}, x::String) = error("Not yet implemented.")

Base.convert(::Type{String}, x::VectorBackedUTF8String) = error("Not yet implemented.")

Base.String(x::VectorBackedUTF8String) = error("Not yet implemented.")

Base.Symbol(x::VectorBackedUTF8String) = error("Not yet implemented.")
