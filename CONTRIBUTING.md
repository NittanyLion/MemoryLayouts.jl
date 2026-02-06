# Contributing to MemoryLayouts.jl

Thank you for your interest in contributing to MemoryLayouts.jl! We welcome contributions from everyone.

## Reporting Bugs

If you find a bug, please open an issue on GitHub. Please include:
- A minimal reproducible example.
- The version of Julia and MemoryLayouts.jl you are using.
- The full error message and stack trace.

## Running Tests

To run the tests locally:

1. Open a Julia REPL in the package directory.
2. Enter package mode by pressing `]`.
3. Run `test`:
   ```julia
   (MemoryLayouts) pkg> test
   ```

## Development Workflow

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Make your changes.
4. Add tests to `test/runtests.jl` (or new files in `test/`) to verify your changes.
5. Ensure all tests pass.
6. Submit a Pull Request.

## Code Style

- We follow standard Julia coding conventions.
- Please respect the existing style of the codebase.
- We use `StyledStrings` for colored output.

## Safety First

Since this package deals with unsafe memory operations:
- Always ensure that `layout` and `deeplayout` maintain safety invariants unless `livedangerously=true` is used.
- Add comments explaining any `unsafe_wrap` or pointer arithmetic.
