function [textures, profile] = build_circle_with_cap(n_background, n_pillar, ...
        n_cap, n_substrate, p1, ~, h_cap, height)
% BUILD_CIRCLE_WITH_CAP  RETICOLO geometry for a circular pillar with cap layer.
%
%   [textures, profile] = build_circle_with_cap(n_background, n_pillar,
%       n_cap, n_substrate, p1, ~, h_cap, height)
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
%       p1           : diameter of the circular pillar (micrometres)
%       ~            : second geometric parameter — unused for this shape
%       h_cap        : thickness of the cap layer
%       height       : thickness of the pillar layer
%
%   OUTPUTS
%       textures : 1x4 cell array for RETICOLO res1()
%       profile  : RETICOLO profile cell array for res2() / res3()
%
%   LAYER STACK (top -> bottom, matching profile order):
%       texture 1 : uniform background (air)         thickness 0
%       texture 2 : cap disc   (n_cap)               thickness h_cap
%       texture 3 : pillar disc (n_pillar)            thickness height
%       texture 4 : uniform substrate                thickness 0
%
%   The disc is represented as a RETICOLO ellipse inclusion with equal
%   Lx = Ly = diameter and N = 36 staircase steps. N >= 5 is recommended
%   by the RETICOLO documentation; 36 gives a smooth circular boundary.
%
%   NOTE: top and bottom bounding layers carry zero thickness because they
%   are physically semi-infinite. If you need field visualisation with res3,
%   give these layers small but non-zero thicknesses in a separate
%   visualisation profile (see compute_field.m for the pattern).

    diameter = p1;
    N_staircase = 36;   % staircase steps for disc approximation

    textures = cell(1, 4);

    % texture 1: semi-infinite background (top)
    textures{1} = n_background;

    % texture 2: cap layer — circular disc of n_cap in background
    textures{2} = { n_background, ...
        [0, 0, diameter, diameter, n_cap, N_staircase] };

    % texture 3: pillar layer — circular disc of n_pillar in background
    textures{3} = { n_background, ...
        [0, 0, diameter, diameter, n_pillar, N_staircase] };

    % texture 4: semi-infinite substrate (bottom)
    textures{4} = n_substrate;

    % profile: layer thicknesses and texture labels, ordered top -> bottom
    profile = { [0, h_cap, height, 0], [1, 2, 3, 4] };
end
