# Taken from https://gist.github.com/JeffBezanson/6b7f1785bb7f2509cbd5d4ff1380556d
# By Jeff Bezanson

import Base: endof, sizeof, pointer, next
using Base: UTF_ERR_INVALID_INDEX, is_valid_continuation, utf8_trailing, utf8_offset

type Str <: AbstractString
    len::Int
    function Str(p::Union{Ptr{Int8},Ptr{UInt8}}, n::Integer)
        s = ccall(:jl_gc_allocobj, Any, (Csize_t,), n+sizeof(Int))
        ps = pointer_from_objref(s)
        unsafe_store!(convert(Ptr{Ptr{Void}}, ps), pointer_from_objref(Str), 0)
        unsafe_store!(convert(Ptr{Int}, ps), n)
        ccall(:memcpy, Void, (Ptr{Void}, Ptr{Void}, Csize_t),
              ps + sizeof(Int), p, n)
        return s
    end
end

Str(d::Union{Vector{Int8},Vector{UInt8}}) = Str(pointer(d), length(d))
Str(s::String) = Str(s.data)

endof(s::Str) = s.len
sizeof(s::Str) = s.len

pointer(s::Str) = convert(Ptr{UInt8}, pointer_from_objref(s)+sizeof(Int))

@noinline function slow_utf8_next(p::Ptr{UInt8}, b::UInt8, i::Int, l::Int)
    if is_valid_continuation(b)
        throw(UnicodeError(UTF_ERR_INVALID_INDEX, i, unsafe_load(p,i)))
    end
    trailing = utf8_trailing[b + 1]
    if l < i + trailing
        return '\ufffd', i+1
    end
    c::UInt32 = 0
    for j = 1:(trailing + 1)
        c <<= 6
        c += unsafe_load(p,i)
        i += 1
    end
    c -= utf8_offset[trailing + 1]
    return Char(c), i
end

@inline function next(s::Str, i::Int)
    if i < 1 || i > s.len
        throw(BoundsError(s,i))
    end
    p = pointer(s)
    b = unsafe_load(p, i)
    if b < 0x80
        return Char(b), i+1
    end
    return slow_utf8_next(p, b, i, s.len)
end
