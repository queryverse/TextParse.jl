if VERSION < v"0.6.0-dev"
    datatype_name(t) = t.name.name
    include("fast-dates.jl")

    include("Str.jl")
else
    const Str = String
    import Base.Dates: CONVERSION_SPECIFIERS, TimeType, DatePart, tryparsenext, character_codes, genvar, CONVERSION_TRANSLATIONS, CONVERSION_DEFAULTS, _directives, DateLocale

    datatype_name(x) = Base.datatype_name(x)
    include("date-tryparse-internal.jl")
    const ISODateFormat = Base.Dates.ISODateFormat
    const ISODateTimeFormat = Base.Dates.ISODateTimeFormat
    const RFC1123Format = Base.Dates.RFC1123Format
end

