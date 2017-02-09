immutable IRef{T}
    value::T
    IRef() = new()
    IRef(value) = new(value)
end

immutable Result{T,S}
    issuccess::Bool
    value::IRef{T}
    error::IRef{S}
    function Result(issuccess, val)
        issuccess ?
            new(issuccess, IRef{T}(val), IRef{S}()) :
            new(issuccess, IRef{T}(), IRef{S}(val))
    end
end

immutable FailedResult end
immutable SuccessResult end

issuccess(e::Result) = e.issuccess
value(e::Result) = e.issuccess ? e.value.value : throw(FailedResult())
geterror(e::Result) = e.issuccess ? throw(SuccessResult()) : e.error.value
