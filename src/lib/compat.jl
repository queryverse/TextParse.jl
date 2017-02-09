if VERSION < v"0.6.0-dev"
    include("fast-dates.jl")

    include("Str.jl")
    Base.readline(arg; chomp=false) = readline(arg)
else
    const Str = String
    import Base.Dates: SLOT_RULE, TimeType, DatePart, tryparsenext, slot_order, slot_defaults, slot_types

    include("date-tryparse-internal.jl")
    const ISODateFormat = Base.Dates.ISODateFormat
    const ISODateTimeFormat = Base.Dates.ISODateTimeFormat
end

