use bidiff::DiffParams;
use std::{
    fs::{self, File},
    io::{BufWriter, Write},
    time::Instant,
};

use comde::com::Compressor;
use comde::zstd::ZstdCompressor;

// Originally inspired from example in:
// https://github.com/divvun/bidiff/blob/main/crates/bic/src/main.rs
// and then hacked down to just service our needs.

// comde is just a wrapper around various compression/decompression libraries.
// and we could just depend on the zstd crate directly if we end up using
// zstd long term.

fn main() {
    let mut args = std::env::args();
    args.next(); // skip program name
    let older = args.next().expect("path to base file");
    let newer = args.next().expect("path to new file");
    let patch = args.next().expect("path to output file");

    let start = Instant::now();

    let older_contents = fs::read(older).expect("read base file");
    let newer_contents = fs::read(newer).expect("read new file");

    let (mut patch_r, mut patch_w) = pipe::pipe();
    let diff_params = DiffParams::new(1, None).unwrap();
    std::thread::spawn(move || {
        bidiff::simple_diff_with_params(
            &older_contents[..],
            &newer_contents[..],
            &mut patch_w,
            &diff_params,
        )
        .unwrap();
    });

    let compressor = ZstdCompressor::new();

    let mut compatch_w = BufWriter::new(File::create(patch).expect("create patch file"));
    compressor
        .compress(&mut compatch_w, &mut patch_r)
        .expect("compress patch");
    compatch_w.flush().expect("flush patch");

    println!("Completed in {:?}", start.elapsed());
}
