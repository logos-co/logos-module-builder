//! A minimal Rust Logos module.
//!
//! Rust-FIRST authoring: the trait below IS the contract. The builder derives
//! the `.lidl` from it (`codegen.rust.trait` in metadata.json), generates the
//! C-ABI scaffold around it, and compiles this crate to a staticlib — no
//! `build.rs`, no committed `.lidl`.
//!
//! Its methods are the module's API, callable by other modules and by
//! `logoscore call`. Signatures use the types LIDL maps one-to-one: `String`,
//! `i64`, `u64`, `f64`, `bool`, `Vec<u8>`, `Option<T>`.

/// Every required method is a module method; the defaulted `on_context_ready`
/// hook is framework plumbing, not part of the API.
///
/// The trait NAME is not free: the scaffold refers to the module name from
/// metadata.json in PascalCase, with `Module` appended unless it already ends
/// in it — `minimal_rust` -> `MinimalRustModule`. `Send + 'static` is required
/// because the generated dispatch stores the impl as a `Box<dyn Any + Send>`.
pub trait MinimalRustModule: Send + 'static {
    /// Returns a greeting and announces it as a typed `greeted` event.
    fn greet(&mut self, name: String) -> String;

    /// Returns a short status string.
    fn get_status(&mut self) -> String;

    /// Called once the module is wired to the host. `ctx` carries the
    /// host-stamped instance id and persistence path.
    fn on_context_ready(&mut self, _ctx: &RustModuleContext) {}
}

/// Typed events — the Rust analog of the C++ `logos_events:` section. Each
/// method becomes an `emit_<name>` free function; other modules subscribe with
/// `modules().minimal_rust.on_greeted(...)`.
pub trait MinimalRustModuleEvents {
    fn greeted(&self, greeting: String);
}

// The builder injects the generated scaffold here — the `install` entry point,
// `RustModuleContext`, `context()`, `modules()` (typed dependency clients) and
// the `emit_*` event emitters. No build.rs, no OUT_DIR.
include!(concat!(env!("CARGO_MANIFEST_DIR"), "/generated/provider_gen.rs"));

#[derive(Default)]
struct Minimal;

impl MinimalRustModule for Minimal {
    fn greet(&mut self, name: String) -> String {
        let greeting = format!("Hello, {}! Greetings from the minimal Rust module.", name);

        // Routes the typed payload to every subscriber. Emitters take their
        // string arguments by reference.
        emit_greeted(&greeting);

        greeting
    }

    fn get_status(&mut self) -> String {
        "Minimal Rust module is running.".to_string()
    }
}

#[no_mangle]
pub extern "Rust" fn logos_module_install() {
    install::<Minimal>();
}
