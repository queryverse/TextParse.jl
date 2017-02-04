include("Str.jl")
include("substringarray.jl")

using BenchmarkTools

const str = randstring(10^6)
const maxwidth=100
const idxs = [begin
              i = rand(1:(10^6-maxwidth))
            j = rand((1:maxwidth)+i)
            StrRange(i:j)
        end for _=1:10^6]
const substrs = SubStringArray(str, idxs)
