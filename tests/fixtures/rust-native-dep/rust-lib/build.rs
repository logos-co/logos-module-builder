// Proves the builder feeds metadata `nix.rust` system deps into the crate
// compile: `pkg-config` (nix.rust.packages.build -> nativeBuildInputs) must be on
// PATH and `zlib` (nix.rust.packages.runtime -> buildInputs) on PKG_CONFIG_PATH
// for this probe to succeed. Without the nix.rust block this build script panics
// and the module fails to build — so a successful build IS the regression test.
fn main() {
    pkg_config::Config::new()
        .probe("zlib")
        .expect("rust-native-dep fixture: zlib not found via pkg-config — nix.rust wiring missing");
}
