// Rebuild when the hooks change, as they are embedded in the binary
fn main() {
    println!("cargo:rerun-if-changed=hooks");
}
