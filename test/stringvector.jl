using TextParse: StringVector
using Base.Test

@testset "StringVector" begin
    s = "Julia is a name without special letters such as æ, ø, and å. Such letters require more than a single byte when encoded in UTF8"
    @testset "split on $splits" for splits in (['.'], [',', '.', ' '])
        sa     = split(s, splits)
        svinit = StringVector(sa)
        @testset "version" for sv in (copy(svinit),
                                   copy!(similar(svinit), svinit),
                                   StringVector(PooledArrays.PooledArray(sa)))
            @test sa == sv
            @test sort(sa) == sort(sv)
            @test copy(sv) == sv

            @testset "setindex with UnsafeString" begin
                # important to start with end because of special branch when
                # lengths are empty and setting last element
                tmp = sv[end]
                sv[end] = "🍕"
                @test sv[end] == "🍕"

                sv[end] = tmp
                sv[1]   = sv[1]
                @test sa == sv
            end

            @testset "setindex with String" begin
                sv[1]   = sa[1]
                sv[end] = sa[end]
                @test sa == sv
            end

            push!(sv, "🍕") == push!(copy(sa), "🍕")
            @test length(empty!(sv)) == 0
        end
    end

    @testset "A broken case" begin
        sv = StringVector(["JuliaDB", "TextParse"])
        @test length(resize!(sv, 1)[1]) == 7
    end

    @testset "Another broken case" begin
        sv = StringVector(["TextParse", "TextParse", "JuliaDB", "TextParse", "TextParse", "TextParse", "TextParse", "JuliaDB", "JuliaDB"])
        sv[end] = "Dagger"
        sv[1] = "Dagger"
        filter(r"JuliaDB", sv)
    end
end