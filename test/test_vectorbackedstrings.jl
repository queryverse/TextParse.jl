using Test
using TextParse: VectorBackedUTF8String

@testset "VectorBackedStrings" begin
    
buffer = UInt8['T', 'e', 's', 't']

s = VectorBackedUTF8String(buffer)

@test s == VectorBackedUTF8String(copy(buffer))

@test pointer(s) == pointer(buffer)

@test pointer(s, 2) == pointer(buffer, 2)

@test ncodeunits(s) == length(buffer)

@test codeunit(s) <: UInt8

@test codeunit(s, 2) == UInt8('e')

@test thisind(s, 2) == 2

@test isvalid(s, 2) == true

@test iterate(s) == ('T', 2)

@test iterate(s, 2) == ('e', 3)

@test iterate(s, 5) == nothing

@test string(s) == "Test"

sub_s = SubString(s, 2:3)

@test sub_s == "es"

@test pointer(sub_s, 1) == pointer(s, 2)
@test pointer(sub_s, 2) == pointer(s, 3)

@test_throws ErrorException s == "Test"
@test_throws ErrorException "Test" == s
@test_throws ErrorException hash(s, UInt(1))
@test_throws ErrorException print(s)
@test_throws ErrorException textwidth(s)
@test_throws ErrorException convert(VectorBackedUTF8String, "foo")
@test_throws ErrorException convert(String, s)
@test_throws ErrorException String(s)
@test_throws ErrorException Symbol(s)
    
end
