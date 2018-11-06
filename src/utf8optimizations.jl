@inline function eatwhitespaces(str::String, i=1, len=lastindex(str))
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

@inline function eatnewlines(str::String, i=1, len=lastindex(str))
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

@inline function tryparsenext_base10_digit(T,str::String,i, len)
    i > len && @goto error
    @inbounds b = codeunit(str,i)
    diff = b-0x30
    diff >= Int8(10) && @goto error
    return convert(T, diff), i+1

    @label error
    return nothing
end

@inline _isdigit(b::UInt8) = ( (0x30 ≤ b) & (b ≤ 0x39) )

@inline function parse_uint_and_stop(str::String, i, len, n::T) where {T <: Integer}
    ten = T(10)
    # specialize handling of the first digit so we can return an error
    max_without_overflow = div(typemax(T)-9,10) # the larg
    i <= len || return n, false, i
    @inbounds b = codeunit(str, i)
    diff = b-0x30
    if diff < Int8(10) && n <= max_without_overflow
        n *= ten
        n += T(diff)
    else
        return n, false, i
    end
    i += 1

    while i <= len && n <= max_without_overflow
        @inbounds b = codeunit(str, i)
        diff = b-0x30
        if diff < Int8(10)
            n *= ten
            n += T(diff)
        else
            return n, true, i
        end
        i += 1
    end
    return n, true, i
end

@inline function read_digits(str::String, i, len)
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

@inline function _is_e(str::String, i)
    @inbounds b = codeunit(str, i)
    return  (b==0x65) | (b==0x45)
end

@inline function _is_negative(str::String, i)
    @inbounds b = codeunit(str, i)
    return b==0x2d
end

@inline function _is_positive(str::String, i)
    @inbounds b = codeunit(str, i)
    return b==0x2b
end

@inline function tryparsenext(::Numeric{F}, str::String, i, len) where {F<:AbstractFloat}
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
            f = F(f1)*10.0^exp
        else
            f = F(f1)/10.0^(-exp)
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
