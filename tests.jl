using Base.Test

include("csvfast.jl")

const TEST = Dict("primitives"=>Dict(),
                  "fields"=>Dict(),
                  "records"=>Dict())

## Primitives

# Unsigned
const umax = string(typemax(UInt))
TEST["primitives"][Prim{UInt}()] = Dict(
    :valid => [
        "123"=>(123, 4),
        "0"=>(0, 2),
        umax=>(typemax(UInt), length(umax)+1)
    ],
    :invalid => [
        ""=>1, "-1"=>1, "+1"=>1, "1-"=>2,
    ]
)

# Signed
const smax = string(typemax(Int))
const smin = string(typemax(Int))
TEST["primitives"][Prim{Int}()] = Dict(
    :valid => [
        "123"=>(123, 4),
        "+123"=>(123, 5),
        "-123"=>(-123, 5),
        "-0"=>(0, 3),
        smax=>(typemax(Int), length(smax)+1),
        smin=>(typemax(Int), length(smin)+1),
    ],
    :invalid => [
        ""=>1, "x"=>1, "1-"=>2,
    ]
)

valid_check(x) = (get(x[1]), x[2])
invalid_check(x) = x[2]

function test_primitives(TEST)
    @testset "Primitives" begin
        prims = TEST["primitives"]
        @testset "$(string(tok))" for (tok, data) in prims
           #isvalid = get(data, :check_valid, check_valid)
           #isinvalid = get(data, :check_invalid, check_invalid)
            @testset "valid" begin
                for (inp, res) in prims[tok][:valid]
                    @test tryparsenext(tok, inp, 1, length(inp)) |> valid_check == res
                end
            end
            @testset "valid" begin
                for (inp, res) in prims[tok][:invalid]
                    @test tryparsenext(tok, inp, 1, length(inp)) |> invalid_check == res
                end
            end
        end
    end
end

test_primitives(TEST)


## Fields
