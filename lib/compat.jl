if VERSION < v"0.6.0-dev"
    include("lib/fast-dates.jl")

    include("lib/Str.jl")
else
    const Str = String
end
