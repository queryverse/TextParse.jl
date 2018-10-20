struct IRef{T}
    value::T
    IRef{T}() where {T} = new{T}()
    IRef{T}(value) where {T} = new{T}(value)
end

function Base.show(io::IO, r::IRef)
    if isdefined(r, :value)
        print(io, r.value)
    else
        print(io, "∘")
    end
end

struct Result{T,S}
    issuccess::Bool
    value::IRef{T}
    error::IRef{S}
    function Result{T,S}(issuccess, val) where {T,S}
        issuccess ?
            new{T,S}(issuccess, IRef{T}(val), IRef{S}()) :
            new{T,S}(issuccess, IRef{T}(), IRef{S}(val))
    end
end

struct FailedResult end
struct SuccessResult end

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
