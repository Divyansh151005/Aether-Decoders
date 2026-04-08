//! Integer LLR capacities for hardware-friendly Union-Find.

/// Map an independent error probability to doubled integer capacity \(W_e\).
///
/// \(C_e = \max(1, \lfloor \lambda \ln((1-p)/p)\rfloor)\), \(W_e = 2 C_e\).
pub fn integer_capacity(p: f64, lambda: f64) -> u32 {
    let p = p.clamp(1e-15, 1.0 - 1e-15);
    let llr = ((1.0 - p) / p).ln();
    let scaled = (lambda * llr).floor().max(1.0);
    let c = scaled as u32;
    c.saturating_mul(2).max(2)
}

/// Default \(\lambda\) used when compiling Stim detector error models.
pub const DEFAULT_LAMBDA: f64 = 1_000.0;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smaller_p_is_heavier() {
        let light = integer_capacity(0.1, DEFAULT_LAMBDA);
        let heavy = integer_capacity(0.001, DEFAULT_LAMBDA);
        assert!(heavy > light);
        assert_eq!(light % 2, 0);
    }
}
