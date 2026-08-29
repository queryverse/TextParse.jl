using TestItemRunner

include("test_textparse.jl")
include("test_vectorbackedstrings.jl")

@run_package_tests
