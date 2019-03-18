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

const default_true_strings = String["true", "True", "T"]

const default_false_strings = String["false", "False", "F"]

const DEFAULT_QUOTES = ('"', '\'')

function guessdateformat(str)

    dts = Any[Date => d for d in common_date_formats]
    dts = vcat(dts, Any[DateTime => d for d in common_datetime_formats])

    for (typ, df) in dts
        x, len = try
            tryparsenext_internal(typ, str, 1, lastindex(str), df)
        catch err
            continue
        end
        if !isnull(x)
            try
                typ(get(x)...)
                if len > lastindex(str)
                    return DateTimeToken(typ, df)
                end
            catch err; end
        end
    end
    return nothing
end

# force precompilation
guessdateformat("xyz")

function getquotechar(x)
    if (length(x) > 0 && x[1] in DEFAULT_QUOTES) && last(x) == x[1]
        return x[1]
    end
    return '\0'
end

function guesstoken(x, opts, @nospecialize(prev_guess)=Unknown(), nastrings=NA_STRINGS, stringarraytype=StringArray)
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
        inner_token = guesstoken(strip(strip(x, q)), opts, prev_inner, nastrings, stringarraytype)
        return Quoted(inner_token, opts.quotechar, opts.escapechar)
    elseif isa(prev_guess, Quoted)
        # but this token is not quoted
        return Quoted(guesstoken(x, opts, prev_guess.inner, nastrings, stringarraytype), opts.quotechar, opts.escapechar)
    elseif isa(prev_guess, NAToken)
        # This column is nullable
        if isna(x, nastrings)
            # x is null too, return previous guess
            return prev_guess
        else
            tok = guesstoken(x, opts, prev_guess.inner, nastrings, stringarraytype)
            if isa(tok, StringToken)
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
                return StringToken(stringarraytype<:StringArray ? StrRange : String)
            end
        elseif x in default_true_strings || x in default_false_strings
            return BooleanToken(Bool)
        else
            # fast-path
            if length(filter(isnumeric, x)) < 4
                return StringToken(stringarraytype<:StringArray ? StrRange : String)
            end

            maybedate = guessdateformat(x)
            if maybedate === nothing
                return StringToken(stringarraytype<:StringArray ? StrRange : String)
            else
                return maybedate
            end
        end
    end
end


