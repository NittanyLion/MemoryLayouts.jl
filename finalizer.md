# Lines 223–233 of `src/layout.jl` — Finalizer & GC Analysis

## Overview

These lines are the core of `deeptransfer` for bitstype arrays. They copy array data
into a shared contiguous buffer `■` and return a new array backed by that buffer.

## Line-by-line

### Lines 223–225: Element-type alignment padding

The current write position in `■` may not be aligned to `sizeof(T)`. These lines
compute the padding needed and advance `offset` so the data starts at a properly
aligned address.

### Lines 226–227: Creating the wrapped array

`unsafe_wrap( Array, Ptr{T}( ▶now ), length( x ); own = false )` creates a Julia
`Array` whose memory is *not* owned by the array itself — it points directly into the
`■` buffer. The `own = false` means `flat` will **not** call `free` on the pointer
when it is collected.

### Line 228: The finalizer

```julia
finalizer( _ -> ( ■; nothing ), flat )
```

This attaches a finalizer closure to `flat` that **captures `■` by reference**. The
closure body `( ■; nothing )` does nothing useful at runtime — its sole purpose is to
keep `■` reachable in the eyes of the garbage collector for as long as `flat` is alive.

**Why this is necessary:** `■` is a local `Vector{UInt8}` created in the caller
(`deeplayout` line 283, or `layout!`, etc.). After the caller returns, nothing on the
stack references `■` anymore. The *only* remaining references to `■` are inside the
finalizer closures attached to the various `flat` arrays. Without line 228, Julia's GC
would see `■` as unreachable, collect it, and free the underlying memory — leaving
`flat` as a dangling pointer (use-after-free).

### Lines 229–232: Reshape, advance, copy, return

Reshape to the original dimensions, advance the write cursor, copy the source data in,
and wrap the result to preserve the original array type.

## When would Julia kill the memory `flat` points to?

The memory is freed when **all** of the following happen:

1. **Every array backed by `■` becomes unreachable** — that means `flat`, `dest`, the
   return value of `newarrayofsametype`, and anything the caller stores it in, all
   become garbage.
2. **The GC runs** and collects those array objects.
3. **The finalizer closures are collected** — once `flat` is collected, the closure
   `_ -> ( ■; nothing )` is also unreachable.
4. **`■` becomes unreachable** — with no finalizer closures (or anything else) holding
   a reference, `■` itself becomes garbage.
5. **The GC collects `■`** — Julia frees the underlying `UInt8` buffer, and all the
   memory that every `flat` array was pointing into is gone.

A single `deeplayout` call may produce *many* wrapped arrays (one per bitstype array in
the structure), and they all share the same `■`. The buffer stays alive as long as
**any one** of those wrapped arrays is still reachable — because each one's finalizer
independently holds `■`. The memory only dies when the *last* one is collected.
