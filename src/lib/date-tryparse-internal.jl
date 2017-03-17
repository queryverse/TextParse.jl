@generated function tryparse_internal{T<:TimeType, S, F}(::Type{T}, str::AbstractString, df::DateFormat{S, F}, pos::Int, len, endchar=Char(0xff1), raise::Bool=false)
    token_types = Type[dp <: DatePart ? SLOT_RULE[first(dp.parameters)] : Void for dp in F.parameters]
    N = length(F.parameters)

    types = slot_order(T)
    num_types = length(types)
    order = Vector{Int}(num_types)
    for i = 1:num_types
        order[i] = findfirst(token_types, types[i])
    end

    field_defaults = slot_defaults(T)
    field_order = tuple(order...)
    tuple_type = slot_types(T)

    # `slot_order`, `slot_defaults`, and `slot_types` return tuples of the same length
    assert(num_types == length(field_order) == length(field_defaults))

    quote
        R = Nullable{$tuple_type}
        t = df.tokens
        l = df.locale

        err_idx = 1
        Base.@nexprs $N i->val_i = 0
        Base.@nexprs $N i->(begin
            pos > len && @goto done
            nv, next_pos = tryparsenext(t[i], str, pos, len, l)
            if isnull(nv)
                c, _ = next(str, pos)
                if Char(c) == Char(endchar)
                    @goto done
                end
                @goto error
            end
            val_i, pos = unsafe_get(nv), next_pos
            err_idx += 1
        end)

        @label done
        parts = Base.@ntuple $N val
        return R(reorder_args(parts, $field_order, $field_defaults, err_idx)::$tuple_type), pos

        @label error
        # Note: Keeping exception generation in separate function helps with performance
        raise && throw(gen_exception(t, err_idx, pos))
        return R(), pos
    end
end

function gen_exception(tokens, err_idx, pos)
    if err_idx > length(tokens)
        ArgumentError("Found extra characters at the end of date time string")
    else
        ArgumentError("Unable to parse date time. Expected token $(tokens[err_idx]) at char $pos")
    end
end

#    reorder_args(val, idx, default, default_from)
#
# reorder elements of `val` tuple according to `idx` tuple. Use `default[i]`
# when `idx[i] == 0` or i >= default_from
#
# returns a tuple `xs` of the same length as `idx` where `xs[i]` is
# `val[idx[i]]` if `idx[i]` is non zero, `default[i]` if `idx[i]` is zero.
#
# `xs[i]` is `default[i]` for all i >= `default_from`.
#
#
function reorder_args{N}(val::Tuple, idx::NTuple{N}, default::Tuple, default_from::Integer)
    ntuple(Val{N}) do i
        if idx[i] == 0 || idx[i] >= default_from
            default[i]
        else
            val[idx[i]]
        end
    end
end

