//! A Rust Logos module wrapping an external C library — zlib here, standing in
//! for whatever you are wrapping. Rust-FIRST authoring: the trait below IS the
//! contract, and the builder derives the `.lidl` from it (`codegen.rust.trait`).
//!
//! Three places name the library, and all three are needed:
//!   1. `nix.rust.packages` — so the CRATE compiles against it.
//!   2. `nix.packages.runtime` — so the PLUGIN link can find it.
//!   3. `LINK_LIBRARIES` in CMakeLists.txt — so the plugin link names it. A Rust
//!      staticlib leaves its C symbols undefined; without this the plugin fails
//!      to link on Linux and fails to LOAD on macOS.

// The external library's C API. A real wrapper would get these from a `*-sys`
// crate or a bindgen-generated module rather than hand-declaring them.
//
// Everything here is fully qualified on purpose: the generated scaffold is
// `include!`d into this module and already imports the common `std::ffi` names,
// so a `use std::ffi::{c_char, ...}` up here collides with it (E0252).
extern "C" {
    fn zlibVersion() -> *const std::ffi::c_char;
    fn crc32(crc: std::ffi::c_ulong, buf: *const u8, len: std::ffi::c_uint) -> std::ffi::c_ulong;
    fn compressBound(source_len: std::ffi::c_ulong) -> std::ffi::c_ulong;
    fn compress(
        dest: *mut u8,
        dest_len: *mut std::ffi::c_ulong,
        source: *const u8,
        source_len: std::ffi::c_ulong,
    ) -> std::ffi::c_int;
}

/// Every required method is a module method; the defaulted `on_context_ready`
/// hook is framework plumbing, not part of the API.
///
/// The trait NAME is not free: the scaffold refers to the module name from
/// metadata.json in PascalCase, with `Module` appended unless it already ends
/// in it — `rust_external_lib` -> `RustExternalLibModule`. `Send + 'static` is
/// required because dispatch stores the impl as a `Box<dyn Any + Send>`.
pub trait RustExternalLibModule: Send + 'static {
    /// The external library's own version string.
    fn library_version(&mut self) -> String;

    /// CRC-32 of `data`, computed by the external library.
    fn checksum(&mut self, data: String) -> u64;

    /// Deflate `data` and report how many bytes it took, announcing the result
    /// as a typed `compressed` event.
    fn compressed_size(&mut self, data: String) -> u64;

    fn on_context_ready(&mut self, _ctx: &RustModuleContext) {}
}

/// Typed events — the Rust analog of the C++ `logos_events:` section. Each
/// method becomes an `emit_<name>` free function; other modules subscribe with
/// `modules().rust_external_lib.on_compressed(...)`.
pub trait RustExternalLibModuleEvents {
    fn compressed(&self, original: u64, deflated: u64);
}

// The builder injects the generated scaffold here — the `install` entry point,
// `RustModuleContext`, `context()`, `modules()` and the `emit_*` emitters.
include!(concat!(env!("CARGO_MANIFEST_DIR"), "/generated/provider_gen.rs"));

#[derive(Default)]
struct ExternalLib;

impl RustExternalLibModule for ExternalLib {
    fn library_version(&mut self) -> String {
        // SAFETY: zlibVersion() returns a static NUL-terminated string.
        unsafe { std::ffi::CStr::from_ptr(zlibVersion()).to_string_lossy().into_owned() }
    }

    fn checksum(&mut self, data: String) -> u64 {
        let bytes = data.as_bytes();
        // SAFETY: bytes/len describe a live slice for the duration of the call.
        unsafe { crc32(0, bytes.as_ptr(), bytes.len() as std::ffi::c_uint) as u64 }
    }

    fn compressed_size(&mut self, data: String) -> u64 {
        let source = data.as_bytes();
        // SAFETY: the destination buffer is sized by the library's own bound,
        // and `dest_len` is updated in place with the bytes actually written.
        let deflated = unsafe {
            let mut dest_len = compressBound(source.len() as std::ffi::c_ulong);
            let mut dest = vec![0u8; dest_len as usize];
            if compress(
                dest.as_mut_ptr(),
                &mut dest_len,
                source.as_ptr(),
                source.len() as std::ffi::c_ulong,
            ) != 0
            {
                return 0;
            }
            dest_len as u64
        };

        // Routes the typed payload to every subscriber.
        emit_compressed(source.len() as u64, deflated);

        deflated
    }
}

#[no_mangle]
pub extern "Rust" fn logos_module_install() {
    install::<ExternalLib>();
}
