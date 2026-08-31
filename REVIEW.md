# MemoryLayouts.jl — problems and how to fix them

Review of the working tree at commit `28a7ae6` plus uncommitted changes, 2026-08-28.
**Status: every item below has been addressed in the working tree (same day).**  For #5 the
finalizer idea turned out to be unsound (a finalizer closure does *not* keep its captures alive);
the implemented fix uses a `WeakKeyDict` keyed on each array's `Memory` instead.
Findings are ordered by severity. Every item marked **verified** was reproduced by
running code against the package; the rest are from reading the source.

Quick summary:

| # | Severity | Problem |
|---|----------|---------|
| 1 | blocking | `Pkg.test()` fails: LiveServer is a stale hard dependency (Aqua) |
| 2 | bug | `layout` crashes on structs whose array fields are not `Array` (ranges, views, `BitArray`, …) |
| 3 | bug | `deeplayout` swallows errors and silently returns `nothing` |
| 4 | bug | `DivideError` for arrays whose element type has `sizeof == 0` |
| 5 | design | Default (no handle) usage leaks every backing buffer forever |
| 6 | design | `memories` vector pins objects that keep nothing alive |
| 7 | safety | `withlayout` / `release!` make escaped arrays dangling pointers, not "invalidated" |
| 8 | safety | Global handle is not thread safe |
| 9 | dead code | InlineStrings extension defines a method that is never called |
| 10 | API | `exclude` semantics differ between struct / dict / array paths |
| 11 | API | Aliased arrays are duplicated instead of shared |
| 12 | API | `show(::LayoutStats)` is multi-line; `visualizelayout` returns inconsistent types |
| 13 | polish | `prsz` rounding is inconsistent |
| 14 | polish | Banner printed from `__init__` |
| 15 | docs | `Agents.md`, `finalizer.md`, README, docstrings describe the old finalizer design |
| 16 | docs | `docs/Project.toml` lacks BenchmarkTools, which the `@example` blocks use |
| 17 | hygiene | Stray files: `src/*.mem`, `bugger.jl`, `makeandviewdocs.jl`, `finalizer.md`, `examples/Manifest.toml` |
| 18 | tests | No tests for handles, `withlayout`, `exclude`, cycles, stats, visualization, extensions; robustness suite not in CI |
| 19 | CI | Redundant doctest step; only one Julia version tested |

---

## 1. `Pkg.test()` is red: LiveServer is a stale hard dependency — **verified**

**Problem.** The uncommitted `Project.toml` change adds `LiveServer` to `[deps]`
(and `[compat]`). Nothing in `src/` uses it. Aqua fails twice:

```
Stale dependencies: Test Failed … Base.PkgId(… "LiveServer")
Persistent tasks:   Test Failed …
```

The persistent-tasks failure is a side effect: loading LiveServer (via HTTP.jl) leaves
tasks running. With Aqua and JET removed, the 17 functional tests pass, so this is the
only reason CI would be red.

**Cause.** `makeandviewdocs.jl` runs `Pkg.add( "LiveServer" )` while the *package*
project is active, which writes it into `Project.toml`.

**Fix.**

```bash
git restore Project.toml          # drops LiveServer; keeps the keyword reorder if you re-apply it
```

and change `makeandviewdocs.jl` so it never touches the package environment:

```julia
# run with: julia makeandviewdocs.jl
using Pkg
Pkg.activate( "docs" )
Pkg.develop( path = "." )
Pkg.add( "LiveServer" )          # goes into docs/Project.toml, which is fine
Pkg.instantiate()
include( "docs/make.jl" )
using LiveServer
LiveServer.serve( dir = "docs/build" )
```

Alternatively add LiveServer only to `docs/Project.toml` by hand and drop the
`Pkg.add` line altogether.

---

## 2. `layout` crashes on structs whose array fields are not plain `Array` — **verified**

**Problem.** `transferadvance` (`src/layout.jl:160-163`) accepts *any*
`AbstractArray` with an isbits element type, copies it into an `unsafe_wrap`ped
`Array`, and hands that back to `constructorof( T )`. If the field type is anything
other than `Array` (or a registered wrapper), the constructor cannot convert:

```julia
struct R; r :: UnitRange{Int}; v :: Vector{Float64}; end
layout( R( 1:10, rand( 3 ) ) )
# MethodError: Cannot `convert` an object of type Vector{Int64} to an object of type UnitRange{Int64}
```

Same for `SubArray` fields (verified), `BitArray` (silently becomes `Vector{Bool}`,
which is also a type change), `StaticArrays.MArray`, and any lazy array such as
`Fill`, `LinearIndices`, or a huge `1:10^12` (which would try to allocate terabytes
in `computesizedeep`).

**Fix.** Make transferability opt-in by type rather than "anything that is an
`AbstractArray`". A small trait does it and gives the extensions a clean hook:

```julia
# only these get moved into the block; everything else is passed through untouched
transferable( :: Type ) = false
transferable( :: Type{<:Array} ) = true

# in transferadvance / deeptransfer, replace
#     x isa AbstractArray || return x
# with
transferable( typeof( x ) ) || return x
```

and in the extensions:

```julia
MemoryLayouts.transferable( :: Type{<:KeyedArray{T,N,A}} ) where {T,N,A} = MemoryLayouts.transferable( A )
MemoryLayouts.transferable( :: Type{<:OffsetArray{T,N,A}} ) where {T,N,A} = MemoryLayouts.transferable( A )
MemoryLayouts.transferable( :: Type{<:NamedDimsArray{L,T,N,A}} ) where {L,T,N,A} = MemoryLayouts.transferable( A )
```

Apply the same predicate in `computesize`, `computesizedeep`, `computestats`,
`computestatsdeep`, `getblock`, and `collectblocksdeep` so the dry-run functions
count exactly what `layout` would move (right now `layoutstats( [1:10, 1:20] )`
reports 0 blocks while `layout` on the same data would try, and fail, to move them).

---

## 3. `deeplayout` swallows errors and returns `nothing` — **verified**

**Problem.** `src/layout.jl:359-370`:

```julia
try
    return constructorof(T)( ... )
catch
    println( "I choked on a field of type $T; please exclude fields with such types ..." )
finally
    ...
end
```

The `catch` prints to stdout and then falls off the end, so the method returns
`nothing`. `deeplayout( R( 1:10, rand( 3 ) ) )` returns `nothing` with exit code 0.
One level up, `constructorof( Outer )( nothing, ... )` fails too, so the message is
printed once per nesting level and the caller ends up with `nothing` instead of data.
JET also cannot see through this.

**Fix.** Rethrow with context and let the caller decide:

```julia
catch e
    throw( ArgumentError( "deeplayout could not rebuild a $T from its laid-out fields \
        ($(sprint( showerror, e ))); exclude the offending field via `exclude`" ) )
```

With fix #2 in place this path becomes much rarer anyway, because unsupported array
types are passed through untouched instead of being converted.

---

## 4. `DivideError` for zero-size element types — **verified**

**Problem.** `src/layout.jl:172` and `:333`:

```julia
pad = ( sizeof( T ) - ( currentaddr % sizeof( T ) ) ) % sizeof( T )
```

`Nothing`, `Tuple{}`, and empty structs are isbits with `sizeof == 0`, so
`layout( [ fill( nothing, 3 ), rand( 2 ) ] )` throws `DivideError`.

**Fix.** Skip such arrays early, in the same place as the zero-length check:

```julia
( length( x ) == 0 || sizeof( 𝒯 ) == 0 ) && return x
```

and treat them as size 0 in `computesize` / `computesizedeep`.

---

## 5. Default usage leaks every backing buffer — **verified**

**Problem.** When neither a `handle` nor `withlayout` is used, `_register_backing`
stores the buffer in `_global_handle.backing` (`src/layout.jl:51-56`). Nothing ever
removes it. One hundred calls to `layout( [ rand( 10 ) ] )` leave 100 entries in the
global handle; a long-running session that calls `layout` in a loop grows without
bound until the user remembers `release_all!()`. The README's first example
(`@btime … setup = ( X = layout( original() ) )`) does exactly this, leaking about
4 MB per benchmark sample.

The robustness test `test/robustness/memory_leak.jl` would catch this, but it is not
run by CI (see #18).

**Fix (recommended).** Tie the buffer's lifetime to the arrays that point into it,
which is what users expect from a `copy`-like function, and make handles the opt-in
for bulk release rather than the default. Julia keeps a finalizer's captured objects
alive for as long as the finalized object is alive, so:

```julia
function pinbacking( flat, ■ )
    finalizer( _ -> ( ■; nothing ), flat.ref.mem )     # the Memory, not the Array
    return flat
end
```

Attaching the finalizer to `flat.ref.mem` (the `Memory{T}`) rather than to `flat`
matters: `reshape( flat, size( x ) )` for matrices creates a *different* `Array`
sharing the same `Memory`, so a finalizer on `flat` alone would let the buffer be
freed while the reshaped matrix is still in use. That is very likely the crash
`bugger.jl` was chasing before the switch to global storage.

Then:

- no handle and no scope → finalizer only, no global registration, no leak;
- `withlayout` / explicit handle → register in the handle *in addition*, so
  `release!` still drops the references early for people who want deterministic
  release.

If you prefer to keep the current model, at minimum add a `@warn maxlog = 1` the
first time the global handle is used, and say in the README that the default mode
requires `release_all!()`.

---

## 6. `memories` pins objects that keep nothing alive

**Problem.** `_pin_memory( flat, memories )` (`src/layout.jl:58-60`) pushes
`flat.ref.mem` into `handle.memories`. That `Memory` was created by
`unsafe_wrap( …; own = false )`: it does not own the bytes, and its being alive has
no effect on whether `■` is alive. The only thing that keeps `■` alive is the
`backing` IdDict. So `memories` is pure overhead (112 entries after the probe run)
with no safety benefit.

**Fix.** Delete `_pin_memory`, the `memories` field, and the `memories` keyword
threaded through `transferadvance` / `deeptransfer`. If you adopt the finalizer
approach from #5, that replaces it; if not, `backing` already does the job.

---

## 7. Escaped arrays after `release!` are dangling, not "invalidated"

**Problem.** `release!` just calls `empty!` on the dict, so `■` becomes collectable.
Any array that escaped the `withlayout` block still holds a raw pointer into it. The
probe `x = withlayout() do; layout( [ rand( 10 ) ] ); end; GC.gc(); sum( x[1] )`
happened to return a sane number because the pages had not been reused yet; under
memory pressure it is use-after-free — a silent wrong answer or a segfault. The docs
say "invalidated", which suggests a clean error.

**Fix.** Two options, in order of preference:

1. Adopt #5: with a finalizer on the `Memory`, an escaped array keeps its buffer
   alive and is simply *valid*; `release!` becomes "drop my references early".
2. Keep the current semantics but document it honestly: "using an array after its
   handle is released is undefined behavior (use-after-free)". Do not use the word
   "invalidated".

---

## 8. Global handle is not thread safe

**Problem.** `_global_handle.backing` is a plain `IdDict` mutated by every
`layout` call without a handle. Two threads calling `layout` concurrently race on
`setindex!`, which can corrupt the dict.

**Fix.** Add a lock to `LayoutHandle`:

```julia
mutable struct LayoutHandle
    backing :: IdDict{Vector{UInt8}, Nothing}
    lock    :: ReentrantLock
    LayoutHandle() = new( IdDict{Vector{UInt8}, Nothing}(), ReentrantLock() )
end

_register_backing( ■, h :: LayoutHandle ) = @lock h.lock h.backing[■] = nothing
release!( h :: LayoutHandle ) = ( @lock h.lock empty!( h.backing ); nothing )
```

(`withlayout` handles are per-task via `ScopedValue`, so they are fine.)

---

## 9. InlineStrings extension is dead code — **verified**

**Problem.** `ext/MemoryLayoutsInlineStringsExt.jl` defines
`transferadvance( x, TT, ■, offset, alignment )` with five positional arguments.
The package's methods now take eight; nothing calls the five-argument form. It also
still uses `finalizer( _ -> ( ■; nothing ), flat )`, the old ownership model, and
skips the element-alignment padding. `InlineString` types are isbits, so the generic
path already handles them correctly (verified: `layout( [ String3[…], rand( 2 ) ] )`
works with the extension loaded or not).

**Fix.** Delete the extension, its `[weakdeps]` / `[extensions]` / `[compat]` entries,
and the `InlineStrings` test dependency (which the tests never `using`). Keep the
"compatible with InlineStrings" line in the README; it is true by construction. If you
want a test that proves it, add one in `runtests.jl` behind `using InlineStrings`.

---

## 10. `exclude` semantics are inconsistent across paths

**Problem.**

- `deeptransfer` on a struct: excluded fields are `deepcopy`ed (`src/layout.jl:364`).
- `deeptransfer` on a dict: excluded keys keep the *same* object (`:350`) —
  verified: `deeplayout( d; exclude = [:a] )[:a] === d[:a]`.
- `layout` on a struct/dict: excluded fields are shared.
- Arrays: elements cannot be excluded at all (indices are compared against `Symbol[]`).
- `exclude` matches a name at *every* depth: `exclude = [:x]` skips every field
  named `x` anywhere in the tree, which is surprising in a "deep" traversal.

The docstring hedges with "preserved as-is (or deep-copied in some contexts)".

**Fix.** Pick one rule and apply it everywhere. The simplest consistent rule:
`layout` shares excluded values (it is `copy`-like), `deeplayout` deep-copies them
(it is `deepcopy`-like). Change the dict branch of `deeptransfer` to
`D[k] = deepcopy( D[k] )` for excluded keys and say so in the docstring. Document the
"matches at any depth" behavior explicitly, or accept `exclude` as a set of
`Type`s as well as names (`exclude = [ :ptr, Ptr, SubArray ]`), which is usually
what people actually want.

---

## 11. Aliased arrays are duplicated instead of shared

**Problem.** If the same array appears twice in the tree, `layout` warns and
duplicates it (`checkaliasingwarn`). `deepcopy` preserves identity; users coming from
`deepcopy` will expect the same.

**Fix.** Replace the `visited :: IdSet` with an `IdDict{Any,Any}` cache mapping the
original array to its laid-out replacement, and return the cached replacement on the
second encounter. This removes the warning, preserves sharing, uses less memory, and
means `computesize*` should count each distinct array once (thread the same cache
through the size pass, or keep the overestimate — it is only an upper bound).

---

## 12. `show` and `visualizelayout` return-type / IO issues

**Problem.**

- `Base.show( io, ::LayoutStats )` (`src/stats.jl:33`) prints multiple lines. The
  two-argument `show` is supposed to be single-line and parseable-ish; multi-line
  output belongs in `show( io, ::MIME"text/plain", x )`. It also means `[stats]` in a
  vector prints badly.
- `renderblocks` returns `""` when there are no blocks and `nothing` otherwise
  (`src/visualization.jl:33`), prints to `stdout` rather than an `io` argument, and
  the docs page calls `println( visualizelayout( … ) )`, which appends a spurious
  `nothing` line to the rendered docs.

**Fix.** Move the level breakdown into `show( io, ::MIME"text/plain", ls )`; give
`renderblocks` / `visualizelayout` an `io = stdout` keyword and return `nothing`
consistently; drop the `println` wrappers in `docs/src/index.md`.

---

## 13. `prsz` rounding is inconsistent — **verified**

`prsz( 1024 )` → `"1024 b"`, `prsz( 1536 )` → `"1 kb"`, `prsz( 2047 )` → `"1 kb"`,
`prsz( 1500 )` → `"1500 b"`. The `RoundNearestTiesUp` step plus the special case for
`level ≥ 2` produce a scale that jumps at 1536 rather than 1024 and truncates
afterwards.

**Fix.**

```julia
function prsz( units )
    level = 1
    x = float( units )
    while x ≥ 1024 && level < length( sizedescriptor )
        x /= 1024
        level += 1
    end
    return level == 1 ? "$units b" : "$(round( x; digits = 1 )) $(sizedescriptor[level])"
end
```

---

## 14. Banner printed from `__init__`

**Problem.** `__init__` (`src/MemoryLayouts.jl:12-49`) prints a 20-line colored banner
on every `using MemoryLayouts`, including inside downstream packages' test suites,
Distributed workers, CI logs, and the docs build. The opt-out is an environment
variable, which downstream packages cannot set for their users.

**Fix.** Print only in an interactive session, and prefer a `Preferences.jl` setting
(or a `MemoryLayouts.banner()` function) over an environment variable:

```julia
function __init__()
    isinteractive() || return
    get( ENV, "MEMORYLAYOUTS", "" ) ∈ ( "false", "no" ) && return
    banner()
end
```

---

## 15. Documentation describes the previous (finalizer) design

Places that are now wrong or stale:

- `Agents.md`, "Memory Ownership Model": *"Each aligned array has a finalizer that
  keeps the underlying memory block alive. As long as you hold a reference to any of
  the aligned arrays, the memory block is safe."* — false since commit `60f817d`; the
  block lives until `release!`/`release_all!` (or forever, see #5).
- `finalizer.md`: a line-by-line analysis of `src/layout.jl:223-233` that no longer
  exists.
- `docs/src/index.md`, "Things to be mindful of": *"there is overhead … to running
  the finalizer"* and *"the entire memory block is only released if the entire
  collection loses scope"*.
- README visualization sample shows `Min : … (normalized to 0)`; the code prints
  `(leftmost point)`.
- Docstring of `LayoutHandle` says a global store is used "freed by `release_all!()`"
  but nothing warns that not calling it leaks.
- `future/borrow_checker_integration.md` describes the hazard in finalizer terms.

**Fix.** Once you have decided #5, rewrite the ownership section once (in
`docs/src/index.md`), and have `README.md` and `Agents.md` link to it rather than
restate it. Delete `finalizer.md` (or move it to `future/` with a note that it is
historical).

---

## 16. `docs/Project.toml` lacks BenchmarkTools

**Problem.** Both `@example` blocks in `docs/src/index.md` do
`using MemoryLayouts, BenchmarkTools, StyledStrings`, but `docs/Project.toml` lists
only Documenter, MemoryLayouts, StyledStrings. In the CI docs job the examples will
fail; because `warnonly = true` the build still "succeeds" and publishes the error
text instead of the benchmark. (The local `docs/build` was evidently built in a
different environment.)

**Fix.** `julia --project=docs -e 'using Pkg; Pkg.add( "BenchmarkTools" )'`.
Also consider replacing the `@btime` examples with fixed-text `julia` blocks: running
two 10 000-vector benchmarks on every docs build is slow and produces noisy numbers.

---

## 17. Stray files in the repository

| File | What it is | Action |
|------|------------|--------|
| `src/MemoryLayouts.jl.*.mem` (3 files, untracked) | `--track-allocation` output from February | delete; add `*.mem` to `.gitignore` |
| `bugger.jl` (tracked) | debugging script for the old finalizer crash | delete, or turn into a regression test in `test/` |
| `makeandviewdocs.jl` (untracked) | local docs helper that pollutes `Project.toml` (#1) | fix per #1 and either commit it or move to `docs/` |
| `finalizer.md` (tracked) | analysis of code that no longer exists (#15) | delete |
| `examples/Manifest.toml` (tracked) | pins an environment nobody else has | remove; `.gitignore` has `/Manifest*.toml` but not `examples/` |
| `WARP.md` | ignored by git but present | fine as is |
| `test/robustness/report.md` | a status report checked in as test data | move the content to a PR description / `future/` |

---

## 18. Test coverage gaps

`test/runtests.jl` has 17 assertions covering `layout` on struct/dict, `deeplayout`
on struct/dict, and `alignment`. Untested public surface:

- `withlayout`, `LayoutHandle`, `release!`, `release_all!`, the `handle` keyword;
- `exclude` (any path), `livedangerously`;
- cycle detection (`ArgumentError`) and the aliasing warning (only in the
  robustness suite);
- `layoutstats`, `deeplayoutstats`, `visualizelayout`, `deepvisualizelayout`
  (no assertion anywhere);
- every extension: `KeyedArray`, `OffsetArray`, `NamedDimsArray` round-trips
  (the wrappers should survive `layout` with keys/offsets/names intact) — none of
  those packages is even a test dependency;
- the leak check in `test/robustness/memory_leak.jl`;
- error cases from #2, #3, #4 once fixed.

The `test/robustness/` suite is a separate script (`run_robustness.jl`) with its own
`Pkg.activate` and `try/catch` around each module, so failures there never fail
anything.

**Fix.** Fold the robustness modules into `runtests.jl` as ordinary `@testset`s
(drop the `try/catch` and the `println` progress lines), add AxisKeys, OffsetArrays,
NamedDims to `[extras]` / `[targets]`, and add one test per bullet above. Also use
`@test_logs` / `@test_throws` for the safety-check paths.

---

## 19. CI

- The `docs` job runs `julia-docdeploy` and then a separate "Run doctests" step;
  `makedocs` already runs doctests, so the second step is redundant (and fails
  quietly for the reason in #16).
- Only Julia `1.12` is in the matrix. `julia = "1.12"` in compat is fine, but if
  you intend to support 1.11 (the code uses only `Base.ScopedValues` and
  `arr.ref.mem`, both 1.11 features), lower compat to `"1.11"` and add it to the
  matrix; otherwise leave compat as is and remove the ambiguity in the docs.
- `dependabot.yml`, `CompatHelper.yml`, `TagBot.yml` look fine.

---

## Suggested order of work

1. `git restore Project.toml`, fix `makeandviewdocs.jl`, delete the `.mem` files
   (#1, #17) — CI goes green.
2. Transferability trait (#2), zero-size guard (#4), rethrow instead of `println`
   (#3) — correctness.
3. Decide the ownership model (#5), then remove `memories` (#6), add the lock (#8),
   and rewrite the docs once (#7, #15).
4. Remove the InlineStrings extension (#9), settle `exclude` (#10), consider the
   alias cache (#11).
5. Tests (#18), docs environment (#16), `show`/`prsz`/banner polish (#12–#14).
