if VERSION < v"0.6.0-dev"
    include("fast-dates.jl")

    include("Str.jl")
else
    const Str = String

    include("date-tryparse-internal.jl")
    const ISODateFormat = Base.Dates.ISODateFormat
    const ISODateTimeFormat = Base.Dates.ISODateTimeFormat
end

