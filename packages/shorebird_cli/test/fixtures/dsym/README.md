Flat arm64 dSYMs built from `int foo(int x){return x*2;}` in `t.c`:

- `with_debug_info.dwarf`: `clang -arch arm64 -g -c t.c -o t.o`, `clang -arch arm64 -dynamiclib t.o -o t.dylib`, `dsymutil --flat t.dylib -o with_debug_info.dwarf` (69 bytes of `__debug_info`).
- `no_debug_info.dwarf`: the same without `-g`, so dsymutil writes no `__debug_info`, as it does for Dart's snapshot under Xcode 27.
