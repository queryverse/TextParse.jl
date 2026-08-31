@testsnippet TokenCompare begin
    import TextParse: AbstractToken

    # dumb way to compare two AbstractTokens
    Base.:(==)(a::T, b::T) where {T<:AbstractToken} = string(a) == string(b)
end
