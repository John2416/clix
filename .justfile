# Show available recipes
default:
    @just --list

# Automatically format all source files
fmt:
    zig fmt .
    prettier --write .
    just --fmt --unstable

# Run pre-commit hooks on all files
hooks:
    prek run --all-files

# Lint without modifying files
lint:
    zig fmt --check .
    zig build --summary all

# Run tests
test *args:
    zig build test {{ args }} --summary all
