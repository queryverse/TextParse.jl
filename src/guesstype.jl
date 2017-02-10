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

isna(x) = x == "" || x in NA_Strings

function guess_eltype(x, prev_guess=Union{},
                      strtype=StrRange,
                      dateformats=common_date_formats,
                      datetimeformats=common_datetime_formats)

   guess = isna(x) ?
           (issubtype(prev_guess, Nullable) &&
                prev_guess!=Union{} ? prev_guess : Nullable{prev_guess}) :
           !isnull(tryparse(Int64, x)) ? Int64 :
           !isnull(tryparse(Float64, x)) ? Float64 :
           !isnull(tryparse(Float64, x)) ? Float64 :
           Any

   if guess == Any
       dateguess = guessdateformat(x, dateformats, datetimeformats)
       if dateguess !== nothing
           guess = dateguess
       else
           guess = strtype
       end
   end

   t = promote_guess(prev_guess, guess)
   t == Any ? strtype : t
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

let
    @test guessdateformat("2016") |> typeof == DateTimeToken(Date, dateformat"yyyy-mm-dd") |> typeof
    @test guessdateformat("09/09/2016") |> typeof == DateTimeToken(Date, dateformat"mm/dd/yyyy") |> typeof
    @test guessdateformat("24/09/2016") |> typeof == DateTimeToken(Date, dateformat"dd/mm/yyyy") |> typeof
end

promote_guess(T,S) = promote_type(T,S)
promote_guess(d1::DateTimeToken, d2::DateTimeToken) = d2 # TODO: check compatibility
promote_guess(T::Type{Union{}},S::DateTimeToken) = S
promote_guess{S}(T,::Nullable{S}) = Nullable{promote_guess(S,T)}
promote_guess{S<:StringLike}(T, ::S) = S

let
    @test guess_eltype("21") == Int
    @test guess_eltype("") == Nullable{Union{}}
    @test guess_eltype("NA") == Nullable{Union{}}
    @test guess_eltype("21", Nullable{Union{}}) == Nullable{Int}
    @test guess_eltype("", Int) == Nullable{Int}
    @test guess_eltype("", Nullable{Int}) == Nullable{Int}
    @test guess_eltype("21", Float64) == Float64
    @test guess_eltype("\"21\"", Float64, String) == String # Should this be Quoted(Numeric(Float64), required=false) instead?
    @test guess_eltype("abc", Float64, String) == String
    @test guess_eltype("20160909 12:12:12", Union{}) |> typeof == DateTimeToken(DateTime, dateformat"yyyymmdd HH:MM:SS.s") |> typeof
end

