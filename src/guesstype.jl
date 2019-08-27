isna(x, nastrings) = x == "" || x in nastrings

const common_date_formats = Any[
    dateformat"yyyy-mm-dd", dateformat"yyyy/mm/dd",
    dateformat"mm-dd-yyyy", dateformat"mm/dd/yyyy",
    dateformat"dd-mm-yyyy", dateformat"dd/mm/yyyy",
    dateformat"dd u yyyy",  dateformat"e, dd u yyyy"
]

const common_datetime_formats = Any[
    dateformat"yyyy-mm-ddTHH:MM:SS",
    dateformat"yyyy-mm-dd HH:MM:SS",
    ISODateTimeFormat,
    dateformat"yyyy-mm-dd HH:MM:SS.s",
    RFC1123Format,
    dateformat"yyyy/mm/dd HH:MM:SS.s",
    dateformat"yyyymmdd HH:MM:SS.s"
]

const DEFAULT_QUOTES = ('"', '\'')

function guessdateformat(str, len=lastindex(str))

    dts = Any[Date => d for d in common_date_formats]
    dts = vcat(dts, Any[DateTime => d for d in common_datetime_formats])

    for (typ, df) in dts
        x, l = try
            tryparsenext_internal(typ, str, 1, len, df)
        catch err
            continue
        end
        if !isnull(x)
            try
                typ(get(x)...)
                if l > len
                    return DateTimeToken(typ, df)
                end
            catch err; end
        end
    end
    return nothing
end

# force precompilation
guessdateformat("xyz", 3)

function getquotechar(x)
    if (length(x) > 0 && x[1] in DEFAULT_QUOTES) && last(x) == x[1]
        return x[1]
    end
    return '\0'
end

function guesstoken(x, opts, prevent_quote_wrap, @nospecialize(prev_guess=Unknown()), nastrings=NA_STRINGS, stringarraytype=StringArray)
    q = getquotechar(x)

    if isa(prev_guess, StringToken)
        # there is nothing wider than a string
        return prev_guess
    elseif q !== '\0'
        # remove quotes and detect inner token
        if isa(prev_guess, Quoted)
            prev_inner = prev_guess.inner
        else
            prev_inner = prev_guess
        end
        inner_string = strip(strip(x, q))
        if inner_string==""
            # If we come across a "", we classify it as a string column no matter what
            return Quoted(StringToken(stringarraytype<:StringArray ? StrRange : String), opts.quotechar, opts.escapechar)
        else
            inner_token = guesstoken(inner_string, opts, true, prev_inner, nastrings, stringarraytype)
            return Quoted(inner_token, opts.quotechar, opts.escapechar)
        end
    elseif isa(prev_guess, Quoted)
        # but this token is not quoted
        return Quoted(guesstoken(x, opts, true, prev_guess.inner, nastrings, stringarraytype), opts.quotechar, opts.escapechar)
    elseif isa(prev_guess, NAToken)
        # This column is nullable
        if isna(x, nastrings)
            # x is null too, return previous guess
            return prev_guess
        else
            tok = guesstoken(x, opts, false, prev_guess.inner, nastrings, stringarraytype)
            if isa(tok, Quoted) && isa(tok.inner, StringToken)
                return tok # never wrap a string in NAToken
            elseif isa(tok, Quoted)
                # Always put the quoted wrapper on top
                return Quoted(NAToken(tok.inner), opts.quotechar, opts.escapechar)
            else
                return NAToken(tok, nastrings=nastrings)
            end
        end
    elseif isna(x, nastrings)
        return NAToken(prev_guess, nastrings=nastrings)
    else
        # x is neither quoted, nor null,
        # prev_guess is not a NAToken or a StringToken
        ispercent = strip(x)[end] == '%'
        if ispercent
            x = x[1:end-1]
        end
        if tryparse(Int, x) !== nothing || tryparse(Float64, x) !== nothing
            T = tryparse(Int, x) === nothing ? Float64 : Int

            if ispercent
                return Percentage()
            end

            if prev_guess == Unknown()
                return Numeric(T)
            elseif isa(prev_guess, Numeric)
                return Numeric(promote_type(T, fieldtype(prev_guess)))
            else
                # something like a date turned into a single number?
                y1 = StringToken(stringarraytype<:StringArray ? StrRange : String)
                return prevent_quote_wrap ? y1 : Quoted(y1, opts.quotechar, opts.escapechar)
            end
        else
            # fast-path
            if length(filter(isnumeric, x)) < 4
                y2 = StringToken(stringarraytype<:StringArray ? StrRange : String)
                return prevent_quote_wrap ? y2 : Quoted(y2, opts.quotechar, opts.escapechar)
            end

            maybedate = guessdateformat(x)
            if maybedate === nothing
                y3 = StringToken(stringarraytype<:StringArray ? StrRange : String)
                return prevent_quote_wrap ? y3 : Quoted(y3, opts.quotechar, opts.escapechar)
            else
                return maybedate
            end
        end
    end
end


