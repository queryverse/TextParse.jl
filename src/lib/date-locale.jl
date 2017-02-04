
immutable DateLocale
    months::Vector{String}
    months_abbr::Vector{String}
    days_of_week::Vector{String}
    days_of_week_abbr::Vector{String}
    month_value::Dict{String, Int}
    month_abbr_value::Dict{String, Int}
    day_of_week_value::Dict{String, Int}
    day_of_week_abbr_value::Dict{String, Int}
end

function locale_dict{S<:AbstractString}(names::Vector{S})
    result = Dict{String, Int}()

    # Keep both the common case-sensitive version of the name and an all lowercase
    # version for case-insensitive matches. Storing both allows us to avoid using the
    # lowercase function during parsing.
    for i in 1:length(names)
        name = names[i]
        result[name] = i
        result[lowercase(name)] = i
    end
    return result
end

"""
    DateLocale(["January", "February",...], ["Jan", "Feb",...],
               ["Monday", "Tuesday",...], ["Mon", "Tue",...])

Create a locale for parsing or printing textual month names.

Arguments:

- `months::Vector`: 12 month names
- `months_abbr::Vector`: 12 abbreviated month names
- `days_of_week::Vector`: 7 days of week
- `days_of_week_abbr::Vector`: 7 days of week abbreviated

This object is passed as the last argument to `tryparsenext` and `format`
methods defined for each `AbstractDateToken` type.
"""
function DateLocale(months::Vector, months_abbr::Vector,
                    days_of_week::Vector, days_of_week_abbr::Vector)
    DateLocale(
        months, months_abbr, days_of_week, days_of_week_abbr,
        locale_dict(months), locale_dict(months_abbr),
        locale_dict(days_of_week), locale_dict(days_of_week_abbr),
    )
end

const ENGLISH = DateLocale(
    ["January", "February", "March", "April", "May", "June",
     "July", "August", "September", "October", "November", "December"],
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
    ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
)

const LOCALES = Dict{String, DateLocale}("english" => ENGLISH)

for (fn, field) in zip(
    [:dayname_to_value, :dayabbr_to_value, :monthname_to_value, :monthabbr_to_value],
    [:day_of_week_value, :day_of_week_abbr_value, :month_value, :month_abbr_value],
)
    @eval @inline function $fn(word::AbstractString, locale::DateLocale)
        # Maximize performance by attempting to avoid the use of `lowercase` and trying
        # a case-sensitive lookup first
        value = get(locale.$field, word, 0)
        if value == 0
            value = get(locale.$field, lowercase(word), 0)
        end
        value
    end
end

