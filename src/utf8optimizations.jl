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

function tryparsenext(f::Field{T}, str::Union{VectorBackedUTF8String, String}, i, len, opts::LocalOpts{T_ENDCHAR}) where {T, T_ENDCHAR<:UInt8}
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

function tryparsenext(q::Quoted{T,S,<:UInt8,<:UInt8}, str::Union{VectorBackedUTF8String, String}, i, len, opts::LocalOpts{<:UInt8,<:UInt8,<:UInt8}) where {T,S}
    if i>len
        q.required && @goto error
        # check to see if inner thing is ok with an empty field
        @chk2 x, i = tryparsenext(q.inner, str, i, len, opts) error
        @goto done
    end
    @inbounds b = codeunit(str, i)
    ii = i+1
    quotestarted = false
    if q.quotechar == b
        quotestarted = true
        if !q.includequotes
            i = ii
        end

        if q.stripwhitespaces
            i = eatwhitespaces(str, i, len)
        end
    else
        q.required && @goto error
    end

    if quotestarted
        qopts = LocalOpts(q.quotechar, false, q.quotechar, q.escapechar,
                         q.includequotes, q.includenewlines)
        @chk2 x, i = tryparsenext(q.inner, str, i, len, qopts)
    else
        @chk2 x, i = tryparsenext(q.inner, str, i, len, opts)
    end

    if i > len
        if quotestarted && !q.includequotes
            @goto error
        end
        @goto done
    end

    if q.stripwhitespaces
        i = eatwhitespaces(str, i, len)
    end
    i>len && error("Internal error.")
    @inbounds b = codeunit(str, i)
    ii = i + 1

    if quotestarted && !q.includequotes
        b != q.quotechar && @goto error
        i = ii
    end


    @label done
    return Nullable{T}(x), i

    @label error
    return Nullable{T}(), i
end

@inline function isnewline(b::UInt8)
    b == UInt8(10) || b == UInt8(13)
end

function tryparsenext(s::StringToken{T}, str::Union{VectorBackedUTF8String, String}, i, len, opts::LocalOpts{<:UInt8,<:UInt8,<:UInt8}) where {T}
    len = ncodeunits(str)
    inside_quoted_strong = opts.endchar == opts.quotechar
    escapecount = 0
    R = Nullable{T}
    p = UInt8(0)
    i0 = i
    if opts.includequotes
        if i<=len
            @inbounds b = codeunit(str, i)
            if b==opts.quotechar
                # advance counter so that
                # the while loop doesn't react to opening quote
                i += 1
            end
        end
    end

    while i<=len
        @inbounds b = codeunit(str, i)
        ii = i + 1

        if inside_quoted_strong && p==opts.escapechar
            escapecount += 1
        end

        if opts.spacedelim && (b == UInt8(32) || b == UInt8(9)) # 32 = ' ' and 9 = '\t'
            break
        elseif !opts.spacedelim && b == opts.endchar
            if inside_quoted_strong
                # this means we're inside a quoted string
                if opts.quotechar == opts.escapechar
                    # sometimes the quotechar is the escapechar
                    # in that case we need to see the next char
                    if ii > len
                        if opts.includequotes
                            i=ii
                        end
                        break
                    else
                        @inbounds next_b = codeunit(str, ii)
                        if next_b == opts.quotechar
                            # the current character is escaping the
                            # next one
                            i = ii + 1 # skip next char as well
                            p = next_b
                            continue
                        end
                    end
                elseif p == opts.escapechar
                    # previous char escaped this one
                    i = ii
                    p = b
                    continue
                end
            end
            if opts.includequotes
                i = ii
            end
            break
        elseif (!opts.includenewlines && isnewline(b))
            break
        end
        i = ii
        p = b
    end

    return R(_substring(T, str, i0, i-1, escapecount, opts)), i
end

@inline function _substring(::Type{String}, str::Union{VectorBackedUTF8String, String}, i, j, escapecount, opts::LocalOpts{<:UInt8,<:UInt8,<:UInt8})
    if escapecount > 0
        buffer = Vector{UInt8}(undef, j-i+1-escapecount)
        cur_i = i
        cur_buffer_i = 1
        @inbounds c = codeunit(str, cur_i)
        if opts.includequotes && c==opts.quotechar
            @inbounds buffer[cur_buffer_i] = c
            cur_i += 1
            cur_buffer_i += 1
        end
        while cur_i <= j
            @inbounds c = codeunit(str, cur_i)
            if c == opts.escapechar
                next_i = cur_i + 1
                if next_i <= j
                    @inbounds next_c = codeunit(str, next_i)
                    if next_c == opts.quotechar
                        @inbounds buffer[cur_buffer_i] = next_c
                        cur_buffer_i += 1
                        cur_i = next_i
                    end
                else
                    @inbounds buffer[cur_buffer_i] = c
                    cur_buffer_i += 1
                end
            else
                @inbounds buffer[cur_buffer_i] = c
                cur_buffer_i += 1
            end
            cur_i += 1
        end
        return String(buffer)
    else
        return unsafe_string(pointer(str, i), j-i+1)
    end
end

function tryparsenext(na::NAToken{T}, str::Union{VectorBackedUTF8String, String}, i, len, opts::LocalOpts{<:UInt8,<:UInt8,<:UInt8}) where {T}
    R = Nullable{T}
    i = eatwhitespaces(str, i, len)
    if i > len
        if na.emptyisna
            @goto null
        else
            @goto error
        end
    end

    @inbounds b = codeunit(str, i)
    ii = i + 1
    if (b == opts.endchar || isnewline(b)) && na.emptyisna
       @goto null
    end

    if isa(na.inner, Unknown)
        @goto maybe_null
    end
    @chk2 x,ii = tryparsenext(na.inner, str, i, len, opts) maybe_null

    @label done
    return R(convert(T, x)), ii

    @label maybe_null
    naopts = LocalOpts(opts.endchar, opts.spacedelim, opts.quotechar,
                       opts.escapechar, false, opts.includenewlines)
    @chk2 nastr, ii = tryparsenext(StringToken(WeakRefString{UInt8}), str, i, len, naopts)
    if !isempty(searchsorted(na.nastrings, nastr))
        i=ii
        i = eatwhitespaces(str, i, len)
        @goto null
    end
    return R(), i

    @label null
    return R(missing), i

    @label error
    return R(), i
end
