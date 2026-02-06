using MemoryLayouts
using Test

@testset "layout! dict" begin
    d = Dict(:a => rand(10), :b => rand(20))
    d_copy = copy(d)

    # Run layout! in-place
    layout!(d)

    # Check that keys are preserved
    @test d[:a] == d_copy[:a]
    @test d[:b] == d_copy[:b]

    # Check contiguity
    pa = pointer(d[:a])
    pb = pointer(d[:b])
    diff = abs(Int(pb) - Int(pa))
    @test diff == sizeof(d[:a]) || diff == sizeof(d[:b])

    # Check that d itself was modified (though Dicts store pointers, so we check the pointers changed)
    # The pointers inside the arrays should be different from the original if they were reallocated
    # But wait, we are modifying the Dict to point to NEW arrays.
    # The arrays in d_copy should point to the old locations

    p_old_a = pointer(d_copy[:a])
    p_new_a = pointer(d[:a])

    # layout! creates new underlying memory, so pointers should be different
    @test p_old_a != p_new_a
end
