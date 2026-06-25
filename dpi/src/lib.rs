//! DPI-C exports for Verilator TBs (Blueprint M26 + Stim M28).
//!
//! See `Docs/Rtl_Dpi_Research`.

use std::cell::RefCell;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::Path;

use aether_decoders::{
    blueprint_golden, blueprint_num_cases, load_stim_rtl_bundle, BlueprintGolden, StimRtlBundle,
};

thread_local! {
    static BP: RefCell<Option<BlueprintGolden>> = RefCell::new(None);
    static STIM: RefCell<Option<StimRtlBundle>> = RefCell::new(None);
    static STIM_SEL: RefCell<usize> = RefCell::new(0);
}

fn with_bp<F, T>(f: F) -> T
where
    F: FnOnce(&BlueprintGolden) -> T,
    T: Default,
{
    BP.with(|cell| cell.borrow().as_ref().map(f).unwrap_or_default())
}

fn with_stim<F, T>(f: F) -> T
where
    F: FnOnce(&StimRtlBundle, usize) -> T,
    T: Default,
{
    STIM.with(|cell| {
        let sel = STIM_SEL.with(|s| *s.borrow());
        cell.borrow()
            .as_ref()
            .map(|b| f(b, sel))
            .unwrap_or_default()
    })
}

// ----- Blueprint (M26) -----

#[no_mangle]
pub extern "C" fn aether_dpi_num_cases() -> i32 {
    blueprint_num_cases() as i32
}

#[no_mangle]
pub extern "C" fn aether_dpi_load(case_id: i32) -> i32 {
    if case_id < 0 {
        return -1;
    }
    match blueprint_golden(case_id as usize) {
        Some(g) => {
            BP.with(|cell| *cell.borrow_mut() = Some(g));
            0
        }
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn aether_dpi_n() -> i32 {
    with_bp(|g| g.n as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_m() -> i32 {
    with_bp(|g| g.m as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_syn(i: i32) -> i32 {
    with_bp(|g| g.syndrome.get(i as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_bnd(i: i32) -> i32 {
    with_bp(|g| g.is_boundary.get(i as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_eu(e: i32) -> i32 {
    with_bp(|g| g.eu.get(e as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_ev(e: i32) -> i32 {
    with_bp(|g| g.ev.get(e as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_cap(e: i32) -> i32 {
    with_bp(|g| g.cap.get(e as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_exp_cycles() -> i32 {
    with_bp(|g| g.cycles as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_exp_solid() -> i32 {
    with_bp(|g| g.solid_mask as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_exp_corr() -> i32 {
    with_bp(|g| g.corr_mask as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_exp_peel_ops() -> i32 {
    with_bp(|g| g.peel_ops as i32)
}

// ----- Stim (M28): flat buffers, per-edge solid/corr -----

/// Load DEM JSON + shots file; keep up to `max_cases` nontrivial RTL cases.
/// Returns 0 on success, -1 on error (message on stderr).
#[no_mangle]
pub unsafe extern "C" fn aether_dpi_stim_prepare(
    dem_path: *const c_char,
    shots_path: *const c_char,
    max_cases: i32,
) -> i32 {
    if dem_path.is_null() || shots_path.is_null() || max_cases <= 0 {
        eprintln!("aether_dpi_stim_prepare: bad args");
        return -1;
    }
    let dem = match CStr::from_ptr(dem_path).to_str() {
        Ok(s) => s,
        Err(_) => {
            eprintln!("aether_dpi_stim_prepare: dem_path utf8");
            return -1;
        }
    };
    let shots = match CStr::from_ptr(shots_path).to_str() {
        Ok(s) => s,
        Err(_) => {
            eprintln!("aether_dpi_stim_prepare: shots_path utf8");
            return -1;
        }
    };
    match load_stim_rtl_bundle(Path::new(dem), Path::new(shots), max_cases as usize) {
        Ok(b) => {
            eprintln!(
                "DPI stim prepare OK: V={} E={} cases={} (checked {} shots)",
                b.n,
                b.m,
                b.cases.len(),
                b.shots_checked
            );
            STIM.with(|cell| *cell.borrow_mut() = Some(b));
            STIM_SEL.with(|s| *s.borrow_mut() = 0);
            0
        }
        Err(e) => {
            eprintln!("aether_dpi_stim_prepare: {e}");
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_num_cases() -> i32 {
    STIM.with(|cell| {
        cell.borrow()
            .as_ref()
            .map(|b| b.cases.len() as i32)
            .unwrap_or(0)
    })
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_select(case_id: i32) -> i32 {
    STIM.with(|cell| {
        let n = cell
            .borrow()
            .as_ref()
            .map(|b| b.cases.len())
            .unwrap_or(0);
        if case_id < 0 || (case_id as usize) >= n {
            return -1;
        }
        STIM_SEL.with(|s| *s.borrow_mut() = case_id as usize);
        0
    })
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_n() -> i32 {
    with_stim(|b, _| b.n as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_m() -> i32 {
    with_stim(|b, _| b.m as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_bnd(i: i32) -> i32 {
    with_stim(|b, _| b.is_boundary.get(i as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_eu(e: i32) -> i32 {
    with_stim(|b, _| b.eu.get(e as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_ev(e: i32) -> i32 {
    with_stim(|b, _| b.ev.get(e as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_cap(e: i32) -> i32 {
    with_stim(|b, _| b.cap.get(e as usize).copied().unwrap_or(0) as i32)
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_syn(i: i32) -> i32 {
    with_stim(|b, sel| {
        b.cases
            .get(sel)
            .and_then(|c| c.syndrome.get(i as usize).copied())
            .unwrap_or(0) as i32
    })
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_exp_cycles() -> i32 {
    with_stim(|b, sel| b.cases.get(sel).map(|c| c.cycles as i32).unwrap_or(0))
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_exp_peel_ops() -> i32 {
    with_stim(|b, sel| b.cases.get(sel).map(|c| c.peel_ops as i32).unwrap_or(0))
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_exp_solid_bit(e: i32) -> i32 {
    with_stim(|b, sel| {
        b.cases
            .get(sel)
            .and_then(|c| c.solid.get(e as usize).copied())
            .map(|x| if x { 1 } else { 0 })
            .unwrap_or(0)
    })
}

#[no_mangle]
pub extern "C" fn aether_dpi_stim_exp_corr_bit(e: i32) -> i32 {
    with_stim(|b, sel| {
        b.cases
            .get(sel)
            .and_then(|c| c.corr.get(e as usize).copied())
            .map(|x| if x { 1 } else { 0 })
            .unwrap_or(0)
    })
}
