using TestItemRunner

include("test_textparse.jl")
include("test_vectorbackedstrings.jl")
include("test_missing_sink.jl")

@run_package_tests
