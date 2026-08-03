# A reusable native + Wasm C-library pattern

`image_ffmpeg` is intended to become a template rather than a one-off wrapper.
The invariant is **one portable C ABI, two transport adapters, one Dart API**.

## Layers

1. **Upstream source**: vendored or fetched at a pinned revision.
2. **Portable shim**: fixed-width C functions that hide upstream structs and
   platform facilities.
3. **Native build**: Dart build hook produces a code asset; `ffigen` produces
   `@Native` declarations.
4. **Browser build**: Emscripten produces an ES module and Wasm binary; a Worker
   owns the module and its linear memory.
5. **Dart facade**: conditional imports choose an adapter behind one async API.
6. **Parity suite**: identical fixtures exercise both adapters.

## ABI rules

A shim suitable for both FFI and Wasm should:

- use `uint8_t`, `uint32_t`, and other fixed-width types;
- expose opaque handles rather than upstream structs;
- represent buffers as pointer + byte length;
- define exactly who allocates and frees every buffer;
- return integer status codes and expose stable error text;
- avoid callbacks unless the operation genuinely streams;
- batch work into coarse calls;
- expose an ABI version checked before any other operation;
- avoid `long`, `size_t`, C bitfields, variadic calls, and target-dependent
  structure layouts at the public boundary.

## A candidate manifest

A future generator could consume:

```yaml
name: example_c
source:
  directory: third_party/example
  revision: v1.2.3
shim:
  header: src/example_dart.h
  source: src/example_dart.c
  abi_version: 1
native:
  build_system: cmake
web:
  toolchain: emscripten
  worker: true
exports:
  - example_abi_version
  - example_process
  - example_result_release
```

From that, it can generate the native build hook, `ffigen` configuration,
Emscripten export list, Wasm memory adapter, Worker protocol, conditional Dart
backend, and ABI smoke tests. Library-specific work remains concentrated in the
portable C shim and upstream build flags.

## Things a generator cannot infer safely

- What upstream state belongs behind an opaque handle.
- Whether callbacks can be converted to polling or batched events.
- Browser replacements for filesystem, sockets, threads, `dlopen`, and GPU
  APIs.
- Whether output can be copied, transferred, or wrapped zero-copy.
- Licensing consequences of selected upstream build options.
- Semantic parity when native and Wasm use different SIMD, threads, or math
  implementations.

These should be explicit manifest extensions rather than hidden heuristics.
