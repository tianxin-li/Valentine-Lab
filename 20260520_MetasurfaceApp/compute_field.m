function F = compute_field(spec, wavelength, height, n_substrate, n_pillar, ...
        n_background, n_cap, theta, period, p1, p2, h_cap, pol, nn, npts_per_um)
% COMPUTE_FIELD  On-the-fly EM field map for any registered pillar shape.
%
%   F = compute_field(spec, wavelength, height, n_substrate, n_pillar,
%       n_background, n_cap, theta, period, p1, p2, h_cap, pol, nn, npts_per_um)
%
%   Unified replacement for compute_cross_field. Works for any shape in
%   shape_registry. Used by MetasurfaceExplorer to display field profiles
%   in the x-z plane at y = 0.
%
% -----------------------------------------------------------------------
%   INPUTS  (lengths in micrometres, theta in degrees)
% -----------------------------------------------------------------------
%   spec          : shape spec from shape_registry(shape_name)
%   wavelength    : scalar wavelength in micrometres
%   height        : pillar height in micrometres
%   n_substrate   : substrate refractive index (real scalar)
%   n_pillar      : pillar refractive index at this wavelength (complex OK)
%   n_background  : background index (real scalar, typically 1)
%   n_cap         : cap layer refractive index (real scalar)
%   theta         : angle of incidence in degrees
%   period        : unit-cell pitch in micrometres (square lattice)
%   p1            : first geometric parameter (see shape_registry)
%   p2            : second geometric parameter; pass 1 for 1-param shapes
%   h_cap         : cap layer thickness in micrometres
%   pol           : +1 = TE,  -1 = TM
%   nn            : [1x2] Fourier harmonic counts (optional, default [12 12])
%                   Lower values (e.g. [6 6]) give faster GUI response.
%   npts_per_um   : z-sampling density in points per micrometre
%                   (optional, default 30). Uniform across all layers so
%                   pcolor displays layer heights proportionally.
%
% -----------------------------------------------------------------------
%   OUTPUT STRUCT F
% -----------------------------------------------------------------------
%   .x, .z          coordinate vectors.
%                   z = 0 is set at the pillar base (substrate top).
%                   z increases upward (toward air).
%   .Ex .Ey .Ez     [Nz x Nx] complex E-field components
%   .Hx .Hy .Hz     [Nz x Nx] complex H-field components
%   .Eabs           sqrt(|Ex|^2 + |Ey|^2 + |Ez|^2)
%   .Habs           sqrt(|Hx|^2 + |Hy|^2 + |Hz|^2)
%   .index          [Nz x Nx] complex refractive-index map
%   .z_sub_top      z of substrate/pillar interface  (= 0 by construction)
%   .z_pil_top      z of pillar/cap interface        (= height)
%   .z_cap_top      z of cap/air interface           (= height + h_cap)
%   .pillar_xwidth  x-extent of pillar at y=0 = p1 for all shapes
%                   (diameter, width, or major arm width depending on shape)
%   .shape_name     spec.shape_name  (for GUI display logic)
%   .pol, .wavelength   echoed inputs
%
% -----------------------------------------------------------------------
%   DESIGN NOTE — two profiles
% -----------------------------------------------------------------------
%   The production geometry (from spec.build_fn) uses zero thickness for
%   the bounding air and substrate layers because they are semi-infinite.
%   That is correct for res1/res2 (eigensolver and diffraction solve).
%
%   However, res3 uses the profile thickness to determine how far into each
%   layer to sample z-points. A zero-thickness layer gets no z-extent in
%   the output, making the field map end abruptly at the pillar boundary.
%
%   Solution: pass a separate VISUALISATION profile to res3 with small but
%   non-zero thicknesses for the bounding layers. The RETICOLO docs
%   explicitly support redefining the profile before calling res3.
%   The bounding-layer thicknesses only control how much of each semi-
%   infinite region is visualised; they do not affect what was solved.

    if nargin < 14 || isempty(nn)
        nn = [12, 12];
    end
    if nargin < 15 || isempty(npts_per_um)
        npts_per_um = 30;
    end

    % --- RETICOLO setup -------------------------------------------------
    parm              = res0;
    parm.not_io       = 1;
    parm.sym.x        = 0;
    parm.sym.y        = 0;
    parm.sym.pol      = pol;
    parm.res1.champ   = 1;     % REQUIRED for accurate fields in structured layers

    retio({}, inf*1i);         % clear stale RETICOLO state

    % --- geometry via shape registry ------------------------------------
    [textures, profile_solve] = call_shape_builder(spec, ...
        n_background, n_pillar, n_cap, n_substrate, ...
        p1, p2, h_cap, height);

    % --- incidence ------------------------------------------------------
    % Illuminated from the bottom (substrate side), same as the production
    % solver. theta is interpreted as the air-side/effective angle, so the
    % conserved in-plane wavevector uses the background index.
    delta = 90;
    k_par = n_background * sind(theta);

    % --- eigenmode solve ------------------------------------------------
    aa = res1(wavelength, [period, period], textures, nn, k_par, delta, parm);

    % --- visualisation profile for res3 --------------------------------
    % Give air and substrate small but non-zero thicknesses so they appear
    % in the field map with physically correct z-extent proportional to the
    % pillar height.
    h_sub_vis = max(0.25 * height, 0.10);   % substrate depth shown below pillar
    h_air_vis = max(0.15 * height, 0.05);   % air depth shown above cap

    % Layer order matches profile_solve, replacing zero-thickness bounding
    % layers with finite visual thicknesses while preserving internal slices.
    layer_h = profile_solve{1};
    layer_h(1) = h_air_vis;
    layer_h(end) = h_sub_vis;
    profile_vis = { layer_h, profile_solve{2} };

    % --- z-sampling: uniform density across all layers ------------------
    % Each layer gets a number of z-planes proportional to its thickness,
    % giving equal spacing throughout. This ensures pcolor renders each
    % layer with the physically correct height on screen.
    npts_each         = max(8, round(npts_per_um * layer_h));
    npts_each         = min(npts_each, 150);   % cap to avoid slow GUI response
    parm.res3.npts    = npts_each;
    parm.res3.sens    = -1;    % illuminate from bottom (substrate side)
    parm.res3.trace   = 0;     % suppress RETICOLO auto-plots

    % --- field sampling grid (x-z plane at y = 0) ----------------------
    Nx = 121;
    x  = linspace(-period/2, period/2, Nx);
    y  = 0;

    % Incident field amplitude vector in the {uTM, uTE} basis.
    % TE (pol=+1): E along y  -> pure uTE component -> [0, 1]
    % TM (pol=-1): E in xz    -> pure uTM component -> [1, 0]
    if pol == 1
        einc = [0, 1];
    else
        einc = [1, 0];
    end

    [e, z_raw, index_raw] = res3(x, y, aa, profile_vis, einc, parm);

    % res3 (2D) returns e as [Nz x Nx x Ny x 6]; squeeze the singleton Ny dim
    e         = squeeze(e);
    index_raw = squeeze(index_raw);

    % --- z coordinate: set z=0 at pillar base --------------------------
    % RETICOLO places z=0 at the bottom of the bottom (substrate) layer,
    % which in the visualisation profile is h_sub_vis below the pillar base.
    z = z_raw(:).' - h_sub_vis;

    % --- pack output struct ---------------------------------------------
    F            = struct();
    F.x          = x;
    F.z          = z;
    F.Ex         = e(:, :, 1);
    F.Ey         = e(:, :, 2);
    F.Ez         = e(:, :, 3);
    F.Hx         = e(:, :, 4);
    F.Hy         = e(:, :, 5);
    F.Hz         = e(:, :, 6);
    F.Eabs       = sqrt(abs(F.Ex).^2 + abs(F.Ey).^2 + abs(F.Ez).^2);
    F.Habs       = sqrt(abs(F.Hx).^2 + abs(F.Hy).^2 + abs(F.Hz).^2);
    F.index      = index_raw;

    % Layer interface z-coordinates (after the offset above)
    F.z_sub_top  = 0;               % substrate/pillar interface
    F.z_pil_top  = height;          % pillar/cap interface
    F.z_cap_top  = height + h_cap;  % cap/air interface

    % Pillar x-extent at y=0 for GUI overlay drawing.
    % For all current shapes, p1 is the full x-extent at y=0:
    %   circle  -> diameter
    %   square  -> width
    %   cross   -> major arm width (both arms are present at y=0)
    %   ellipse -> major diameter (along x-axis)
    F.pillar_xwidth = p1;

    % Metadata
    F.shape_name = spec.shape_name;
    F.pol        = pol;
    F.wavelength = wavelength;
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
