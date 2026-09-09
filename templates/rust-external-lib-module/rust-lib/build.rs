// Locates the external C library for the crate compile. `pkg-config` comes from
// metadata.json `nix.rust.packages.build` (-> nativeBuildInputs) and zlib from
// `nix.rust.packages.runtime` (-> buildInputs); Nix sets PKG_CONFIG_PATH so this
// probe finds it inside the sandbox.
//
// The probe emits link flags for the crate, but a Rust staticlib does not carry
// them: the plugin's own link line still has to name the library, which is what
// `LINK_LIBRARIES z` in CMakeLists.txt does.
fn main() {
    pkg_config::Config::new()
        .probe("zlib")
        .expect("zlib not found via pkg-config — check nix.rust in metadata.json");
}
