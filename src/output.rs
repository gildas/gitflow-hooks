//! Console output helpers, mirroring the ones in hooks/common/functions.sh

use std::sync::atomic::{AtomicU8, Ordering};

static VERBOSITY: AtomicU8 = AtomicU8::new(0);

pub fn set_verbosity(level: u8) {
    VERBOSITY.store(level, Ordering::Relaxed);
}

pub fn verbosity() -> u8 {
    VERBOSITY.load(Ordering::Relaxed)
}

/// Prints a section title followed by a line, like the title() bash function
pub fn title(text: &str) {
    let width = 114usize.saturating_sub(text.chars().count());
    eprintln!("\x1b[34;1m▶\x1b[0m \x1b[1m{text} {}\x1b[0m", "𝄙".repeat(width));
}

macro_rules! verbose {
    ($($arg:tt)*) => {
        if $crate::output::verbosity() > 0 { eprintln!($($arg)*); }
    };
}

macro_rules! trace {
    ($($arg:tt)*) => {
        if $crate::output::verbosity() > 1 { eprintln!($($arg)*); }
    };
}

macro_rules! warning {
    ($($arg:tt)*) => {
        eprintln!("\x1b[33mWarning: {}\x1b[m", format!($($arg)*))
    };
}

macro_rules! error {
    ($($arg:tt)*) => {
        eprintln!("\x1b[1;31m❌\x1b[m \x1b[31mError: {}\x1b[m", format!($($arg)*))
    };
}

pub(crate) use {error, trace, verbose, warning};
