typealias StringLike Union{AbstractString, StrRange}

const common_date_formats = Any[dateformat"yyyy-mm-dd", dateformat"yyyy/mm/dd",
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

isna(x) = x == "" || x in NA_STRINGS

const DEFAULT_QUOTES = ('"', ''')

function StringToken(T::Type, opts::LocalOpts)
    StringToken(T, opts.endchar, opts.quotechar, opts.escapechar, opts.includenewlines)
end

function guesstoken(x, opts, prev_guess::ANY=Unknown(),
                      strtype=StrRange,
                      dateformats=common_date_formats,
                      datetimeformats=common_datetime_formats)
    # detect quoting
    if length(x) > 0 && x[1] in DEFAULT_QUOTES && last(x) == x[1]
        # this is a reliable quoted situation
        inner_x = strip(strip(x, x[1]))
        prev = prev_guess
        if isa(prev_guess, Quoted)
            prev = prev_guess.inner
        end

        opts1 = LocalOpts(opts.endchar, x[1], opts.escapechar,
                          opts.includequotes, opts.includenewlines)
        inner = guesstoken(inner_x, opts, prev, strtype,
                             dateformats, datetimeformats)
        return Quoted(inner; quotechar=opts.quotechar, escapechar=opts.escapechar)
    end

    if isa(prev_guess, Quoted)
        # It seems this field is not quoted.
        # promote the inner thing
        inner = guesstoken(x, opts, prev_guess.inner, strtype,
                             dateformats, datetimeformats)
        return Quoted(inner; required=false, quotechar=prev_guess.quotechar,
                             escapechar=prev_guess.escapechar)
    end
    guess::Any = isna(x) ?
           (isa(prev_guess, NAToken) &&
            prev_guess!=Unknown() ? prev_guess : NAToken(prev_guess, endchar=opts.endchar)) :
           !isnull(tryparse(Int64, x)) ? fromtype(Int64) :
           !isnull(tryparse(Float64, x)) ? fromtype(Float64) :
           !isnull(tryparse(Float64, x)) ? fromtype(Float64) :
           Any

   if guess == Any
       dateguess = guessdateformat(x, dateformats, datetimeformats)
       if dateguess !== nothing
           guess = dateguess
       else
           guess = StringToken(strtype, opts)
       end
   end

   t = promote_guess(opts, prev_guess, guess)
   if isa(t, Quoted) && isa(t.inner, NAToken) && isa(t.inner.inner, StringToken)
       @show x, prev_guess, guess, t
   end
   t == Any ? StringToken(strtype, opts) : t
end

function guessdateformat(str, dateformats=common_date_formats,
                         datetimeformats=common_datetime_formats)

    dts = Any[Date => d for d in dateformats]
    dts = vcat(dts, Any[DateTime => d for d in datetimeformats])

    for (typ, df) in dts
        x, len = tryparse_internal(typ, str, df, 1, endof(str))
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

promote_guess(opts, T,S) = fromtype(promote_type(fieldtype(T),fieldtype(S)))

promote_guess(opts, str::StringToken, ::Any) = str
promote_guess(opts,r::Any, str::StringToken) = str
promote_guess(opts, str::StringToken, str2::StringToken) = str2
promote_guess(opts, str::StringToken, na::NAToken) = str

promote_guess(opts, ::Unknown, S::DateTimeToken) = S
promote_guess(opts, T, d::DateTimeToken) = fromtype(StrRange)
promote_guess(opts, d::DateTimeToken, T) = fromtype(StrRange)
promote_guess(opts, d1::DateTimeToken, d2::DateTimeToken) = d2 # TODO: check compatibility

promote_guess(opts, T, na::NAToken) = NAToken(promote_guess(opts, T,na.inner), endchar=na.endchar)
promote_guess(opts, na1::NAToken, na2::NAToken) = NAToken(promote_guess(opts, na2.inner,na1.inner), endchar=na2.endchar) # XXX: na1.endchar == na2.endchar ?

promote_guess(opts, T, q::Quoted) = Quoted(promote_guess(opts, T,q.inner), endchar=q.quotechar, escapechar=q.escapechar, required=false)
promote_guess(opts, q1::Quoted, q2::Quoted) = Quoted(promote_guess(opts, q1.inner,q2.inner), required=q2.required, quotechar=q2.quotechar, escapechar=q2.escapechar) # XXX: are the options same?

