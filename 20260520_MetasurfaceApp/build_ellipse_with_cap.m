function [textures, profile] = build_ellipse_with_cap(n_background, n_pillar, ...
        n_cap, n_substrate, p1, p2, h_cap, height)
% BUILD_ELLIPSE_WITH_CAP  RETICOLO geometry for an elliptical pillar with cap.
%
%   [textures, profile] = build_ellipse_with_cap(n_background, n_pillar,
%       n_cap, n_substrate, p1, p2, h_cap, height)
%
%   Part of the unified geometry-builder family. All builders share this
%   call signature so they can be stored as function handles in shape_registry
%   and called generically by RCWA_solve and compute_field.
%
%   INPUTS  (lengths in micrometres — same units as wavelength)
%       n_background : refractive index of surrounding medium (air)
%       n_pillar     : refractive index of the pillar material (complex OK)
%       n_cap        : refractive index of the cap layer
%       n_substrate  : refractive index of the substrate
%       p1           : major diameter of the ellipse (along x-axis)
%       p2           : aspect ratio = minor_diameter / major_diameter
%                      minor_diameter (along y-axis) = p1 * p2
%                      Valid range: 0 < p2 <= 1  (p2 = 1 gives a circle)
%       h_cap        : thickness of the cap layer
%       height       : thickness of the pillar layer
%
%   OUTPUTS
%       textures : 1x4 cell array for RETICOLO res1()
%       profile  : RETICOLO profile cell array for res2() / res3()
%
%   LAYER STACK (top -> bottom, matching profile order):
%       texture 1 : uniform background (air)           thickness 0
%       texture 2 : cap ellipse   (n_cap)              thickness h_cap
%       texture 3 : pillar ellipse (n_pillar)           thickness height
%       texture 4 : uniform substrate                  thickness 0
%
%   The ellipse axes are aligned with x and y. The major axis is along x
%   (Lx = major_diameter), minor axis along y (Ly = minor_diameter).
%   N = 36 staircase steps are used for the ellipse approximation.
%   N >= 5 is recommended by RETICOLO; 36 gives a smooth boundary.
%
%   NOTE: top and bottom bounding layers carry zero thickness because they
%   are physically semi-infinite. For field visualisation with res3, use
%   a separate visualisation profile with non-zero bounding thicknesses.

    major_diam  = p1;
    minor_diam  = p1 * p2;
    N_staircase = 36;

    textures = cell(1, 4);

    % texture 1: semi-infinite background (top)
    textures{1} = n_background;

    % texture 2: cap layer — ellipse of n_cap in background
    % [cx, cy, Lx, Ly, n, N_staircase]
    textures{2} = { n_background, ...
        [0, 0, major_diam, minor_diam, n_cap,    N_staircase] };

    % texture 3: pillar layer — ellipse of n_pillar in background
    textures{3} = { n_background, ...
        [0, 0, major_diam, minor_diam, n_pillar, N_staircase] };

    % texture 4: semi-infinite substrate (bottom)
    textures{4} = n_substrate;

    % profile: layer thicknesses and texture labels, ordered top -> bottom
    profile = { [0, h_cap, height, 0], [1, 2, 3, 4] };
end
