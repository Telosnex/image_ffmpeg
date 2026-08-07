# ADR 0001: Run web image operations in a Worker pool

- Status: Accepted
- Date: 2026-08-07

## Context

The web backend owns one module Worker and one Wasm runtime. Each Wasm call is synchronous inside that Worker. Concurrent Dart futures therefore run serially.

Native calls use separate helper isolates. This ADR changes only the web backend.

## Decision

The web backend will use a pool of module Workers. Each Worker will own one independent Wasm runtime and process one operation at a time.

`ImageFfmpegWeb.workerCount` will set the pool size. Its default value will be `2`. Valid values will be `1` through `4`. The backend will read this value once during its first initialization. An invalid value will cause a `RangeError`.

The backend will create and initialize all configured Workers in parallel during its first initialization. Every Worker must return the package ABI version. All Workers must return identical `hasFfmpeg` and build-information values. One initialization failure will terminate the full pool and fail backend initialization.

The backend will use one central FIFO queue. An idle Worker will receive the oldest queued operation. Each operation will use one Worker until that operation completes. Operation completion order will not be guaranteed.

The backend will copy caller-owned input bytes when the API operation starts. It will transfer that copy only after a Worker accepts the operation. Worker responses will continue to transfer their output buffers.

A normal FFmpeg error will fail only its operation. A Worker load error or top-level error will fail its active operation and remove that Worker. The backend will make one immediate replacement attempt. A failed replacement will reduce the pool size. Zero live Workers will fail all queued and future operations.

The Worker script will store one runtime initialization promise. This promise will prevent duplicate Wasm initialization inside one Worker.

The implementation will not use Wasm threads, `SharedArrayBuffer`, or Emscripten pthreads. It will not require cross-origin isolation headers.

The implementation will not cancel an active FFmpeg call. Cancellation support requires a separate decision.

## Consequences

Two independent image operations can run in parallel by default. Applications can select serial operation with `workerCount = 1`.

Each Worker adds a Wasm runtime, linear memory, and FFmpeg working memory. The maximum value of `4` limits browser memory and CPU pressure.

The first image operation will include initialization of the full configured pool. Later operations will not pay Worker startup cost.

## Required tests

Browser tests must prove these behaviors in Chrome dart2js, Chrome Dart2Wasm, and Safari dart2js:

1. Two operations overlap with `workerCount = 2`.
2. Operations run serially with `workerCount = 1`.
3. A third operation waits in FIFO order while two Workers are busy.
4. One FFmpeg error does not stop its Worker.
5. One Worker failure triggers one replacement attempt.
6. Input transfer does not detach caller-owned bytes.
7. All Workers reject an ABI mismatch during backend initialization.
