__precompile__()

module TextParse

using CodecZlib, WeakRefStrings, Dates

include("lib/compat.jl")
include("util.jl")
include("field.jl")
include("record.jl")

include("guesstype.jl")
include("csv.jl")

end # module
