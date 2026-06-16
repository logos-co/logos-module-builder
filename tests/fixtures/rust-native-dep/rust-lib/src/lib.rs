//! Fixture module — a Rust cdylib whose crate has a system build dependency
//! (zlib, probed via pkg-config in build.rs). It builds only when the builder
//! feeds metadata `nix.rust` packages into the crate compile. Rust-first
//! authoring (codegen.rust.trait): the trait below is the single source of truth.

/// Trivial IPC contract — the build is the test; the method just makes the
/// module loadable. The defaulted on_context_ready is framework plumbing.
pub trait RustNativeDepModule: Send + 'static {
    fn ping(&mut self) -> String;
    fn on_context_ready(&mut self, _ctx: &RustModuleContext) {}
}

// The builder injects the generated scaffold here (no OUT_DIR; CARGO_MANIFEST_DIR).
include!(concat!(env!("CARGO_MANIFEST_DIR"), "/generated/provider_gen.rs"));

#[derive(Default)]
struct NativeDepImpl;

impl RustNativeDepModule for NativeDepImpl {
    fn ping(&mut self) -> String {
        "ok".to_string()
    }
}

#[no_mangle]
pub extern "Rust" fn logos_module_install() {
    install::<NativeDepImpl>();
}
