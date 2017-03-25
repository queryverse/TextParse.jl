using Compat

immutable IRef{T}
    value::T
    @compat (::Type{IRef{T}}){T}() = new{T}()
    @compat (::Type{IRef{T}}){T}(value) = new{T}(value)
end

function Base.show(io::IO, r::IRef)
    if isdefined(r, :value)
        print(io, r.value)
    else
        print(io, "∘")
    end
end

immutable Result{T,S}
    issuccess::Bool
    value::IRef{T}
    error::IRef{S}
    function (::Type{Result{T,S}}){T,S}(issuccess, val)
        issuccess ?
            new{T,S}(issuccess, IRef{T}(val), IRef{S}()) :
            new{T,S}(issuccess, IRef{T}(), IRef{S}(val))
    end
end

immutable FailedResult end
immutable SuccessResult end

issuccess(e::Result) = e.issuccess
value(e::Result) = e.issuccess ? e.value.value : throw(FailedResult())
geterror(e::Result) = e.issuccess ? throw(SuccessResult()) : e.error.value

function Base.show(io::IO, r::Result)
    if issuccess(r)
        print(io, "✓ $(value(r))")
    else
        print(io, "✗ $(geterror(r))")
    end
end
