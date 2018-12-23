@inline function eatwhitespaces(str::Union{VectorBackedUTF8String, String}, i=1, len=lastindex(str))
    while i<=len
        @inbounds b = codeunit(str, i)

        if b==0x20 # This is ' '
            i += 1
        else
            break
        end
    end
    return i
end

@inline function eatnewlines(str::Union{VectorBackedUTF8String, String}, i=1, len=lastindex(str))
    count = 0
    while i<=len
        @inbounds b = codeunit(str, i)
        if b == 0xd # '\r'
            i += 1
            if i<=len
                @inbounds b = codeunit(str, i)
                if b == 0xa # '\n'
                    i += 1
                end
            end
            count += 1
        elseif b == 0xa
            i += 1
            if i<=len
                @inbounds b = codeunit(str, i)
                if b == 0xd
                    i += 1
                end
            end
            count += 1
        else
            break
        end
    end

    return i, count
end

@inline function tryparsenext_base10_digit(T,str::Union{VectorBackedUTF8String, String},i, len)
    i > len && @goto error
    @inbounds b = codeunit(str,i)
    diff = b-0x30
    diff >= UInt8(10) && @goto error
    return convert(T, diff), i+1

    @label error
    return nothing
end

@inline _isdigit(b::UInt8) = ( (0x30 ≤ b) & (b ≤ 0x39) )

@inline function parse_uint_and_stop(str::Union{VectorBackedUTF8String, String}, i, len, n::T) where {T <: Integer}
    ten = T(10)
    # specialize handling of the first digit so we can return an error
    max_without_overflow = div(typemax(T)-9,10) # the larg
    i <= len || return n, false, i
    @inbounds b = codeunit(str, i)
    diff = b-0x30
    if diff < UInt8(10) && n <= max_without_overflow
        n *= ten
        n += T(diff)
    else
        return n, false, i
    end
    i += 1

    while i <= len && n <= max_without_overflow
        @inbounds b = codeunit(str, i)
        diff = b-0x30
        if diff < UInt8(10)
            n *= ten
            n += T(diff)
        else
            return n, true, i
        end
        i += 1
    end
    return n, true, i
end

@inline function read_digits(str::Union{VectorBackedUTF8String, String}, i, len)
    # slurp up extra digits
    while i <= len
        @inbounds b = codeunit(str, i)
        if !_isdigit(b) # do nothing
            return i
        end
        i += 1
    end
    return i
end

@inline function _is_e(str::Union{VectorBackedUTF8String, String}, i)
    @inbounds b = codeunit(str, i)
    return  (b==0x65) | (b==0x45)
end

@inline function _is_negative(str::Union{VectorBackedUTF8String, String}, i)
    @inbounds b = codeunit(str, i)
    return b==0x2d
end

@inline function _is_positive(str::Union{VectorBackedUTF8String, String}, i)
    @inbounds b = codeunit(str, i)
    return b==0x2b
end

const pre_comp_exp = Float64[10.0^i for i=0:22]

@inline function tryparsenext(::Numeric{F}, str::Union{VectorBackedUTF8String, String}, i, len) where {F<:AbstractFloat}
    R = Nullable{F}

    i>len && @goto error

    negate = false
    @inbounds b = codeunit(str, i)
    if b==0x2d # '-'
        negate = true
        i += 1
    elseif b==0x2b # '+'
        i +=1
    end

    f1::Int64 = 0

    # read an integer up to the decimal point
    f1, rval1, idecpt = parse_uint_and_stop(str, i, len, f1)
    idecpt = read_digits(str, idecpt, len) # get any trailing digits
    i = idecpt

    ie = i
    frac_digits = 0

    # next thing must be dec pt.
    if i <= len && @inbounds(codeunit(str, i)) == 0x2e # Check for '.'
        i += 1
        f1, rval2, ie = parse_uint_and_stop(str, i, len, f1)
        frac_digits = ie - i

        ie = read_digits(str, ie, len) # get any trailing digits
    elseif !rval1 # no first number, and now no deciaml point => invalid
        @goto error
    end

    # Next thing must be exponent
    i = ie
    eval::Int32 = 0

    if i <= len && _is_e(str, i)
        i += 1

        enegate = false
        if i<=len
            if _is_negative(str, i)
                enegate = true
                i += 1
            elseif _is_positive(str, i)
                i += 1
            end
        end
        eval, rval3, i = parse_uint_and_stop(str, i, len, eval)
        if enegate
            eval *= Int32(-1)
        end
    end

    exp = eval - frac_digits

    maxexp = 308
    minexp = -307

    if frac_digits <= 15 && -22 <= exp <= 22
        if exp >= 0
            f = F(f1)*pre_comp_exp[exp+1]
        else
            f = F(f1)/pre_comp_exp[-exp+1]
        end
    else
          f = convert_to_double(f1, exp)
    end

    if negate
        f = -f
    end

    @label done
    return R(convert(F, f)), i

    @label error
    return R(), i
end

function tryparsenext(f::Field{T}, str::String, i, len, opts::LocalOpts{T_ENDCHAR}) where {T, T_ENDCHAR<:UInt8}
    R = Nullable{T}
    i > len && @goto error
    if f.ignore_init_whitespace
        i = eatwhitespaces(str, i, len)
    end
    @chk2 res, i = tryparsenext(f.inner, str, i, len, opts)

    if f.ignore_end_whitespace
        i0 = i

        while i<=len
            @inbounds b = codeunit(str, i)

            !opts.spacedelim && opts.endchar == 0x09 && b == 0x09 && (i = i+1; @goto done) # 0x09 is \t

            b!=0x20 && b!=0x09 && break
            i=i+1
        end

        opts.spacedelim && i > i0 && @goto done
    end
    # todo don't ignore whitespace AND spacedelim

    if i > len
        if f.eoldelim
            @goto done
        else
            @goto error
        end
    end

    i>len && error("Internal error.")
    @inbounds b = codeunit(str, i)
    opts.spacedelim && (b!=0x20 || b!=0x09) && (i+=1; @goto done)
    !opts.spacedelim && opts.endchar == b && (i+=1; @goto done)

    if f.eoldelim
        if b == 0x0d # '\r'
            i+=1
            if i<=len
                @inbounds b = codeunit(str, i)
                if b == 0x0a # '\n'
                    i+=1
                end
            end
            @goto done
        elseif b == 0x0a # '\n'
            i+=1
            if i<=len
                @inbounds b = codeunit(str, i)
                if b == 0x0d # '\r'
                    i+=1
                end
            end
            @goto done
        end
    end

    @label error
    return R(), i

    @label done
    return R(convert(T, res)), i
end
