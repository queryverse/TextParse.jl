using NullableArrays

typealias StringLike Union{AbstractString, StrRange}

isna(x) = x == "" || x in NA_Strings

function guess_eltype(x, prev_guess=Union{}, str_type=StrRange, isna=isna)
   guess = isna(x) ? Nullable{prev_guess} :
           !isnull(tryparse(Int64, x)) ? Int64 :
           !isnull(tryparse(Float64, x)) ? Float64 :
           !isnull(tryparse(Float64, x)) ? Float64 :
           #!isnull(tryparse(DateTime, x)) ? DateTime
           str_type
   t = promote_guess(prev_guess, guess)
   t == Any ? str_type : t
end

promote_guess(T,S) = promote_type(T,S)
promote_guess{S}(T,::Nullable{S}) = Nullable{promote_guess(S,T)}
promote_guess{S<:StringLike}(T, ::S) = S

let
    @test guess_eltype("21") == Int
    @test guess_eltype("") == Nullable{Union{}}
    @test guess_eltype("NA") == Nullable{Union{}}
    @test guess_eltype("21", Nullable{Union{}}) == Nullable{Int}
    @test guess_eltype("", Int) == Nullable{Int}
    @test guess_eltype("21", Float64) == Float64
    @test guess_eltype("\"21\"", Float64) == StrRange # Should this be Quoted(Numeric(Float64), required=false) instead?
    @test guess_eltype("abc", Float64, String) == String
end

