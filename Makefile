all: term
	mkdir -p priv
	mkdir -p priv/macos-arm
	cp native/target/release/libglerm.dylib priv/macos-arm/libglerm.so
	gleam build

term: native/src/lib.rs
	cd native && cargo build --release

clean:
	gleam clean
