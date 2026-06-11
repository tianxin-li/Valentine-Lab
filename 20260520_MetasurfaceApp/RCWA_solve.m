function [transmitted, reflected, trans_efficiency, refl_efficiency, ...
        T_total, R_total] = RCWA_solve(spec, wavelength, height, n_substrate, ...
        n_pillar, n_background, n_cap, theta, period, p1, p2, h_cap, pol, nn)
% RCWA_SOLVE  Unified RCWA solver for any shape registered in shape_registry.
%
%   [transmitted, reflected, trans_efficiency, refl_efficiency] = ...
%       RCWA_solve(spec, wavelength, ...)
%
%   [transmitted, reflected, trans_efficiency, refl_efficiency, ...
%    T_total, R_total] = RCWA_solve(spec, wavelength, ...)
%
%   The first four outputs (0-order only) are always computed.
%   T_total and R_total (5th and 6th outputs) are the sums of efficiency
%   over ALL propagative diffraction orders, and are only extracted when
%   requested via nargout. This adds negligible overhead.
%
% -----------------------------------------------------------------------
%   INPUTS
% -----------------------------------------------------------------------
%   spec         : shape spec struct from shape_registry(shape_name)
%   wavelength   : scalar wavelength in micrometres
%   height       : pillar height in micrometres
%   n_substrate  : substrate refractive index (real scalar, e.g. 1.45)
%   n_pillar     : pillar complex index at this wavelength
%   n_background : background index (real scalar, typically 1 for air)
%   n_cap        : cap layer refractive index (real scalar)
%   theta        : angle of incidence in degrees (0 = normal)
%   period       : unit-cell pitch in micrometres (square lattice)
%   p1           : first geometric parameter (see shape_registry for meaning)
%   p2           : second geometric parameter; pass 1 for 1-parameter shapes
%   h_cap        : cap layer thickness in micrometres
%   pol          : polarization  +1 = TE,  -1 = TM
%   nn           : [1x2] Fourier harmonic counts, e.g. [12 12]
%                  (optional, default [12 12]; raise to check convergence)
%
% -----------------------------------------------------------------------
%   OUTPUTS (0-order — always computed)
% -----------------------------------------------------------------------
%   transmitted      : complex amplitude of 0-order transmitted wave
%   reflected        : complex amplitude of 0-order reflected wave
%   trans_efficiency : power efficiency of 0-order transmission (0 to 1)
%   refl_efficiency  : power efficiency of 0-order reflection   (0 to 1)
%
% -----------------------------------------------------------------------
%   OUTPUTS (all-order sums — computed only when requested via nargout)
% -----------------------------------------------------------------------
%   T_total : sum of efficiency over ALL propagative transmitted orders
%   R_total : sum of efficiency over ALL propagative reflected orders
%
% -----------------------------------------------------------------------
%   ENERGY BALANCE INTERPRETATION
% -----------------------------------------------------------------------
%   T_total + R_total ≈ 1.0  →  negligible absorption (lossless material)
%   T_total + R_total < 1.0  →  (1 - T_total - R_total) fraction absorbed
%
%   Higher-order fraction (energy leaving through non-zero diffracted orders):
%     HOE = (T_total - trans_efficiency) + (R_total - refl_efficiency)
%
%   This cleanly separates higher-order diffraction from absorption.
%   HOE > 0 means the structure is not subwavelength in at least one medium.
%
%   GRATING CUTOFFS (normal incidence, square lattice):
%     First orders propagate in substrate when λ < period × n_substrate
%     First orders propagate in air when      λ < period × n_background
%   Use check_grating_orders() to visualise this over a wavelength range.

    if nargin < 14 || isempty(nn)
        nn = [12, 12];
    end

    if pol ~= 1 && pol ~= -1
        error('RCWA_solve:badPol', 'pol must be +1 (TE) or -1 (TM); got %g', pol);
    end

    % --- RETICOLO parameters --------------------------------------------
    parm          = res0;
    parm.not_io   = 1;
    parm.sym.x    = 0;
    parm.sym.y    = 0;
    parm.sym.pol  = pol;

    retio({}, inf*1i);

    % --- geometry -------------------------------------------------------
    [textures, profile] = call_shape_builder(spec, ...
        n_background, n_pillar, n_cap, n_substrate, ...
        p1, p2, h_cap, height);

    % --- incidence ------------------------------------------------------
    delta = 90;
    k_par = n_background * sind(theta);

    % --- solve ----------------------------------------------------------
    aa     = res1(wavelength, [period, period], textures, nn, k_par, delta, parm);
    result = res2(aa, profile);

    % --- 0-order extraction ---------------------------------------------
    if pol == 1
        transmitted      = result.TEinc_bottom_transmitted.amplitude_TE{0,0};
        trans_efficiency = result.TEinc_bottom_transmitted.efficiency{0,0};
        reflected        = result.TEinc_bottom_reflected.amplitude_TE{0,0};
        refl_efficiency  = result.TEinc_bottom_reflected.efficiency{0,0};
    else
        transmitted      = result.TMinc_bottom_transmitted.amplitude_TM{0,0};
        trans_efficiency = result.TMinc_bottom_transmitted.efficiency{0,0};
        reflected        = result.TMinc_bottom_reflected.amplitude_TM{0,0};
        refl_efficiency  = result.TMinc_bottom_reflected.efficiency{0,0};
    end

    % --- all-order sums (only when caller requests nargout > 4) ---------
    % RETICOLO stores a column vector of efficiencies for every propagative
    % order in result.*_transmitted.efficiency and *_reflected.efficiency.
    % Summing gives the total power fraction in all propagative modes.
    %
    % This is gated on nargout so there is zero overhead when only the
    % standard 4 outputs are used (e.g., inside the production parfor sweep
    % when enable_energy_log = false).
    if nargout > 4
        if pol == 1
            T_total = sum(result.TEinc_bottom_transmitted.efficiency);
            R_total = sum(result.TEinc_bottom_reflected.efficiency);
        else
            T_total = sum(result.TMinc_bottom_transmitted.efficiency);
            R_total = sum(result.TMinc_bottom_reflected.efficiency);
        end
    end
end

function [textures, profile] = call_shape_builder(spec, n_background, ...
        n_pillar, n_cap, n_substrate, p1, p2, h_cap, height)
    if isfield(spec, 'build_options') && ~isempty(spec.build_options)
        [textures, profile] = spec.build_fn(n_background, n_pillar, ...
            n_cap, n_substrate, p1, p2, h_cap, height, spec.build_options);
    else
        [textures, profile] = spec.build_fn(n_background, n_pillar, ...
            n_cap, n_substrate, p1, p2, h_cap, height);
    end
end
