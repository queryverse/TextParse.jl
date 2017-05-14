isna(x) = x == "" || x in NA_STRINGS

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

const DEFAULT_QUOTES = ('"', ''')

function guessdateformat(str, dateformats=common_date_formats,
                         datetimeformats=common_datetime_formats)

    dts = Any[Date => d for d in dateformats]
    dts = vcat(dts, Any[DateTime => d for d in datetimeformats])

    for (typ, df) in dts
        x, len = tryparsenext_internal(typ, str, 1, endof(str), df)
        if !isnull(x)
            try
                typ(get(x)...)
                if len > endof(str)
                    return DateTimeToken(typ, df)
                end
            catch err; end
        end
    end
    return nothing
end

function getquotechar(x)
    if (length(x) > 0 && x[1] in DEFAULT_QUOTES) && last(x) == x[1]
        return x[1]
    end
    return '\0'
end

function guesstoken(x, prev_guess::ANY=Unknown())
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
        inner_token = guesstoken(strip(strip(x, q)), prev_inner)
        return Quoted(inner_token)
    elseif isa(prev_guess, Quoted)
        # but this token is not quoted
        return Quoted(guesstoken(x, prev_guess.inner))
    elseif isa(prev_guess, NAToken)
        # This column is nullable
        if isna(x)
            # x is null too, return previous guess
            return prev_guess
        else
            tok = guesstoken(x, prev_guess.inner)
            if isa(tok, StringToken)
                return tok # never wrap a string in NAToken
            elseif isa(tok, Quoted)
                # Always put the quoted wrapper on top
                return Quoted(NAToken(tok.inner))
            else
                return NAToken(tok)
            end
        end
    elseif isna(x)
        return NAToken(prev_guess)
    else
        # x is neither quoted, nor null,
        # prev_guess is not a NAToken or a StringToken
        ispercent = strip(x)[end] == '%'
        if ispercent
            x = x[1:end-1]
        end
        if !isnull(tryparse(Int, x)) || !isnull(tryparse(Float64, x))
            T = isnull(tryparse(Int, x)) ? Float64 : Int

            if ispercent
                return Percentage()
            end

            if prev_guess == Unknown()
                return Numeric(T)
            elseif isa(prev_guess, Numeric)
                return Numeric(promote_type(T, fieldtype(prev_guess)))
            else
                # something like a date turned into a single number?
                return StringToken(StrRange)
            end
        else
            maybedate = guessdateformat(x)
            if maybedate == nothing
                return StringToken(StrRange)
            else
                return maybedate
            end
        end
    end
end


