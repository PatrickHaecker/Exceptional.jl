using Exceptional
using Test

module StorageSites
using Exceptional

function checked(input)
    @⊤⎋ input > 0 "fixed message"
    return input
end

function other(input)
    @⊤⎋ input > 0 "fixed message"
    return input
end

function unicode(input)
    @⊤⎋ input > 0 "value: \u03b2"
    return input
end
end

function stored_roundtrip(check, output)
    try
        check(-1)
    catch exception
        showerror(output, exception)
        return true
    end
    return false
end

function stored_batch(check, output)
    for iteration in 1:32
        output isa IOBuffer && truncate(output, 0)
        stored_roundtrip(check, output) || return false
    end
    return true
end

function stored_render(holder, output)
    truncate(output, 0)
    showerror(output, holder[])
    return nothing
end

@testset "Automatic exception storage" begin
    slotnames = filter(name -> startswith(string(name), "##once_slot"), names(StorageSites; all=true))
    slots = [getfield(StorageSites, name) for name in slotnames]
    @test length(slots) == 3
    @test all(slot -> slot.holder isa Ref{Any}, slots)
    @test slots[1].holder !== slots[2].holder
    @test slots[2].holder !== slots[3].holder
    @test all(name -> isconst(StorageSites, name), slotnames)
    @test StorageSites.checked(1) == 1
    @test (@allocated StorageSites.checked(1)) == 0
    @test stored_roundtrip(StorageSites.checked, devnull)
    @test (@allocated stored_roundtrip(StorageSites.checked, devnull)) == 0

    for (check, text) in ((StorageSites.checked, "fixed message"),
                          (StorageSites.other, "fixed message"),
                          (StorageSites.unicode, "value: \u03b2"))
        expected = "ArgumentError: " * text
        capacity = ncodeunits(expected)
        output = IOBuffer(Vector{UInt8}(undef, capacity); read=true, write=true, maxsize=capacity)
        @test stored_batch(check, output)
        @test position(output) == capacity
        @test (@allocated stored_batch(check, output)) == 0
        @test String(take!(output)) == expected
    end

    holder = first(slots).holder
    expected = sprint(showerror, holder[])
    capacity = ncodeunits(expected)
    output = IOBuffer(Vector{UInt8}(undef, capacity); read=true, write=true, maxsize=capacity)
    stored_render(holder, output)
    @test (@allocated stored_render(holder, output)) == 0
    @test String(take!(output)) == expected

    try
        StorageSites.checked(-1)
    catch outer
        @test stored_roundtrip(StorageSites.checked, devnull)
        @test outer.msg == "fixed message"
    end
    tasks = [Threads.@spawn stored_roundtrip(StorageSites.checked, devnull) for attempt in 1:8]
    @test all(fetch, tasks)
    @test filter(name -> startswith(string(name), "##once_slot"), names(StorageSites; all=true)) == slotnames
end