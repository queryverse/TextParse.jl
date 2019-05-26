using Nullables

"""
    tryparsenext_internal(::Type{<:TimeType}, str, pos, len, df::DateFormat, raise=false)

Parses the string according to the directives within the DateFormat. The specified TimeType
type determines the type of and order of tokens returned. If the given DateFormat or string
does not provide a required token a default value will be used. When the string cannot be
parsed the returned value tuple will be null if `raise` is false otherwise an exception will
be thrown.

Returns a 2-element tuple `(values, pos)`:
* `values::Nullable{Tuple}`: A tuple which contains a value for each token as specified by
  the passed in type.
* `pos::Int`: The character index at which parsing stopped.
"""
@generated function tryparsenext_internal(
                                          ::Type{T}, str::AbstractString, pos::Int, len::Int, df::DateFormat, endchar=UInt('\0'), raise::Bool=false,
) where {T<:TimeType}
    letters = character_codes(df)

    tokens = Type[CONVERSION_SPECIFIERS[letter] for letter in letters]
    value_names = Symbol[genvar(t) for t in tokens]

    output_tokens = CONVERSION_TRANSLATIONS[T]
    output_names = Symbol[genvar(t) for t in output_tokens]
    output_defaults = ([CONVERSION_DEFAULTS[t] for t in output_tokens]...,)
    R = typeof(output_defaults)

    # Pre-assign output variables to defaults. Ensures that all output variables are
    # assigned as the value tuple returned from `tryparsenext_core` may not include all
    # of the required variables.
    assign_defaults = Expr[
        quote
            $name = $default
        end
        for (name, default) in zip(output_names, output_defaults)
    ]

    # Unpacks the value tuple returned by `tryparsenext_core` into separate variables.
    value_tuple = Expr(:tuple, value_names...)

    assign_value_till = Expr[
    quote
        ($i <= num_parsed) && ($name = unsafe_val[$i])
    end for (i,name) in enumerate(value_names)]

    quote
        values, pos, num_parsed = tryparsenext_core(str, pos, len, df, raise)
        $(assign_defaults...)
        unsafe_val = unsafe_get(values)
        $(assign_value_till...)
        if isnull(values)
            if (pos <= len && str[pos] == Char(endchar)) ||
                num_parsed == $(length(value_names))
                # finished parsing and found an extra char,
                # or parsing was terminated by a delimiter
                return Nullable{$R}($(Expr(:tuple, output_names...))), pos
            end
            return Nullable{$R}(), pos
        end
        return Nullable{$R}($(Expr(:tuple, output_names...))), pos
    end
end

"""
    tryparsenext_core(str::AbstractString, pos::Int, len::Int, df::DateFormat, raise=false)

Parses the string according to the directives within the DateFormat. Parsing will start at
character index `pos` and will stop when all directives are used or we have parsed up to
the end of the string, `len`. When a directive cannot be parsed the returned value tuple
will be null if `raise` is false otherwise an exception will be thrown.

Returns a 3-element tuple `(values, pos, num_parsed)`:
* `values::Nullable{Tuple}`: A tuple which contains a value for each `DatePart` within the
  `DateFormat` in the order in which they occur. If the string ends before we finish parsing
  all the directives the missing values will be filled in with default values.
* `pos::Int`: The character index at which parsing stopped.
* `num_parsed::Int`: The number of values which were parsed and stored within `values`.
  Useful for distinguishing parsed values from default values.
"""
@generated function tryparsenext_core(
    str::AbstractString, pos::Int, len::Int, df::DateFormat, raise::Bool=false,
)
    directives = _directives(df)
    letters = character_codes(directives)

    tokens = Type[CONVERSION_SPECIFIERS[letter] for letter in letters]
    value_names = Symbol[genvar(t) for t in tokens]
    value_defaults = ([CONVERSION_DEFAULTS[t] for t in tokens]...,)
    R = typeof(value_defaults)

    # Pre-assign variables to defaults. Allows us to use `@goto done` without worrying about
    # unassigned variables.
    assign_defaults = Expr[
        quote
            $name = $default
        end
        for (name, default) in zip(value_names, value_defaults)
    ]

    vi = 1
    parsers = Expr[
        if directives[i] <: DatePart
            name = value_names[vi]
            nullable = Symbol(:nullable_, name)
            vi += 1
            quote
                pos > len && @goto done
                nothingable_tuple = tryparsenext(directives[$i], str, pos, len, locale)
                nothingable_tuple===nothing && @goto error
                $name = nothingable_tuple[1]
                next_pos = nothingable_tuple[2]
                pos = next_pos
                num_parsed += 1
                directive_index += 1
            end
        else
            quote
                pos > len && @goto done
                nothingable_tuple = tryparsenext(directives[$i], str, pos, len, locale)
                nothingable_tuple===nothing && @goto error
                nullable_delim = nothingable_tuple[1]
                next_pos = nothingable_tuple[2]
                pos = next_pos
                directive_index += 1
            end
        end
        for i in 1:length(directives)
    ]

    quote
        directives = df.tokens
        locale::DateLocale = df.locale

        num_parsed = 0
        directive_index = 1

        $(assign_defaults...)
        $(parsers...)

        pos > len || @goto error

        @label done
        return Nullable{$R}($(Expr(:tuple, value_names...))), pos, num_parsed

        @label error
        if raise
            if directive_index > length(directives)
                throw(ArgumentError("Found extra characters at the end of date time string"))
            else
                d = directives[directive_index]
                throw(ArgumentError("Unable to parse date time. Expected directive $d at char $pos"))
            end
        end
        return Nullable{$R}($(Expr(:tuple, value_names...)), $(false)), pos, num_parsed
    end
end
