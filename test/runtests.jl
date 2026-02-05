using MemoryLayouts
using Test

struct S
    a::Vector{Float64}
    b::Vector{Float64}
end

@testset "MemoryLayouts.jl" begin
    @testset "layoutmem struct" begin
        s = S(rand(10), rand(20))
        s_aligned = layoutmem(s)

        @test s_aligned.a == s.a
        @test s_aligned.b == s.b
        
        # Check contiguity
        # pointer(b) should be pointer(a) + sizeof(a)
        pa = pointer(s_aligned.a)
        pb = pointer(s_aligned.b)
        @test UInt(pb) == UInt(pa) + sizeof(s_aligned.a)
        
        # Check that we didn't align the original
        # (Originals are usually allocated separately, so unlikely to be contiguous)
        # @test UInt(pointer(s.b)) != UInt(pointer(s.a)) + sizeof(s.a) 
    end
    
    @testset "layoutmem dict" begin
        d = Dict(:a => rand(10), :b => rand(20))
        d_aligned = layoutmem(d)
        
        @test d_aligned[:a] == d[:a]
        @test d_aligned[:b] == d[:b]
        
        # In a dict, order is not guaranteed, but one should follow the other in the block
        # We can just check that they are close in memory
        pa = pointer(d_aligned[:a])
        pb = pointer(d_aligned[:b])
        diff = abs(Int(pb) - Int(pa))
        @test diff == sizeof(d_aligned[:a]) || diff == sizeof(d_aligned[:b])
    end

    @testset "deeplayoutmem" begin
        struct DeepS
            x::S
            y::Vector{Int}
        end
        
        ds = DeepS(S(rand(5), rand(5)), rand(Int, 5))
        ds_aligned = deeplayoutmem(ds)
        
        @test ds_aligned.x.a == ds.x.a
        @test ds_aligned.y == ds.y
        
        # Check that x.a, x.b, and y are all in one block
        p_xa = pointer(ds_aligned.x.a)
        p_xb = pointer(ds_aligned.x.b)
        p_y  = pointer(ds_aligned.y)
        
        # Assuming field order traversal
        @test UInt(p_xb) == UInt(p_xa) + sizeof(ds_aligned.x.a)
        @test UInt(p_y) == UInt(p_xb) + sizeof(ds_aligned.x.b)
    end

    @testset "alignment option" begin
        s = S(rand(10), rand(20)) # 80 bytes and 160 bytes. Both multiples of 8.
        # Let's align to 64 bytes.
        # 80 is not multiple of 64 (64 + 16).
        # So padding of 48 bytes needed? (80 + 48 = 128 = 2*64).
        
        s_aligned = layoutmem(s, alignment=64)
        
        pa = pointer(s_aligned.a)
        pb = pointer(s_aligned.b)
        
        @test mod(UInt(pa), 64) == 0
        @test mod(UInt(pb), 64) == 0
        
        # Check padding
        diff = UInt(pb) - UInt(pa)
        @test diff >= sizeof(s_aligned.a)
        @test mod(diff, 64) == 0
    end
end
