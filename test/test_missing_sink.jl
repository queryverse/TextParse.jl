@testitem "pluggable missing sink" begin
    # A minimal values+mask sink implementing the missingarraytype contract,
    # defined here without any external package.
    struct MaskVector{T} <: AbstractVector{T}
        values::Vector{T}
        isna::Vector{Bool}
    end
    Base.size(v::MaskVector) = size(v.values)
    Base.getindex(v::MaskVector, i::Int) = v.isna[i] ? nothing : v.values[i]
    Base.setindex!(v::MaskVector{T}, x, i::Int) where {T} =
        (v.values[i] = x; v.isna[i] = false; x)
    function Base.resize!(v::MaskVector, n::Integer)
        l = length(v.values)
        resize!(v.values, n)
        resize!(v.isna, n)
        for i = l+1:n
            v.isna[i] = true
        end
        return v
    end

    TextParse.allocmissing(::Type{MaskVector}, ::Type{T}, N) where {T} =
        MaskVector{T}(Vector{T}(undef, N), fill(true, N))
    TextParse.setmissing!(v::MaskVector, i) = (v.isna[i] = true; nothing)
    TextParse.ismissingcolumn(::MaskVector) = true
    TextParse.colmatchestype(v::MaskVector{T}, ::Type{S}) where {T,S} =
        S == Union{Missing,T}
    function TextParse.promotemissing(::Type{MaskVector}, col::Array{Missing}, rowno, ::Type{T}) where {T}
        S = Base.nonmissingtype(T)
        S === Any && (S = Missing)
        return MaskVector{S}(Vector{S}(undef, length(col)), fill(true, length(col)))
    end
    function TextParse.promotemissing(::Type{MaskVector}, col::Vector{S}, rowno, ::Type{T}) where {S,T}
        VT = Base.nonmissingtype(T)
        values = Vector{VT}(undef, length(col))
        isna = fill(true, length(col))
        for i = 1:rowno
            values[i] = col[i]
            isna[i] = false
        end
        return MaskVector{VT}(values, isna)
    end
    function TextParse.promotemissing(::Type{MaskVector}, col::MaskVector{S}, rowno, ::Type{T}) where {S,T}
        VT = Base.nonmissingtype(T)
        VT === S && return col
        values = Vector{VT}(undef, length(col.values))
        for i = 1:rowno
            col.isna[i] || (values[i] = col.values[i])
        end
        return MaskVector{VT}(values, copy(col.isna))
    end

    # Column that is nullable from the start (NA in the type-detect window)
    data = """
    a,b,c
    1,x,1.5
    NA,y,2.5
    3,NA,NA
    """
    cols, names = TextParse._csvread(data, ','; stringarraytype=Array, missingarraytype=MaskVector)
    @test names == ["a", "b", "c"]
    a, b, c = cols
    @test a isa MaskVector{Int}
    @test a.isna == [false, true, false]
    @test a.values[1] == 1 && a.values[3] == 3
    # "NA" in a string column is a valid string, not a missing value
    @test b isa Vector{String}
    @test b == ["x", "y", "NA"]
    @test c isa MaskVector{Float64}
    @test c.isna == [false, false, true]
    @test c.values[2] == 2.5

    # Late promotion: the first missing value appears after the type-detect
    # window, so a plain Vector{Int} column is promoted into the sink mid-parse.
    n = 60
    rows = [string(i) for i in 1:n]
    rows[50] = "NA"
    data2 = "a\n" * join(rows, "\n") * "\n"
    cols2, _ = TextParse._csvread(data2, ','; stringarraytype=Array, missingarraytype=MaskVector)
    col2 = cols2[1]
    @test col2 isa MaskVector{Int}
    @test length(col2.values) == n
    @test col2.isna[50]
    @test count(col2.isna) == 1
    @test col2.values[49] == 49 && col2.values[51] == 51

    # Columns without missing values stay plain Vectors
    cols3, _ = TextParse._csvread("a,b\n1,x\n2,y\n", ','; stringarraytype=Array, missingarraytype=MaskVector)
    @test cols3[1] isa Vector{Int}
    @test cols3[2] isa Vector{String}

    # Guard: plugin sinks require stringarraytype=Array
    @test_throws ArgumentError TextParse._csvread("a\n1\n", ','; missingarraytype=MaskVector)

    # Defaults unchanged: no sink argument gives Union{Missing,T} columns
    cols4, _ = TextParse._csvread(data, ','; stringarraytype=Array)
    @test eltype(cols4[1]) == Union{Missing,Int}
    @test ismissing(cols4[1][2])
end
