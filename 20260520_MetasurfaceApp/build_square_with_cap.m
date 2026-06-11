function [textures, profile] = build_square_with_cap(n_background, n_pillar, ...
        n_cap, n_substrate, p1, ~, h_cap, height)
% BUILD_SQUARE_WITH_CAP  RETICOLO geometry for a square pillar with cap layer.
%
%   [textures, profile] = build_square_with_cap(n_background, n_pillar,
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
%       p1           : side width of the square pillar (micrometres)
%       ~            : second geometric parameter — unused for this shape
%       h_cap        : thickness of the cap layer
%       height       : thickness of the pillar layer
%
%   OUTPUTS
%       textures : 1x4 cell array for RETICOLO res1()
%       profile  : RETICOLO profile cell array for res2() / res3()
%
%   LAYER STACK (top -> bottom, matching profile order):
%       texture 1 : uniform background (air)          thickness 0
%       texture 2 : cap square   (n_cap)              thickness h_cap
%       texture 3 : pillar square (n_pillar)           thickness height
%       texture 4 : uniform substrate                 thickness 0
%
%   The square is represented as a RETICOLO rectangle inclusion with
%   Lx = Ly = width and shape flag = 1 (rectangle). The inclusion is
%   centred at (0, 0) within the unit cell.
%
%   NOTE: top and bottom bounding layers carry zero thickness because they
%   are physically semi-infinite. For field visualisation with res3, use
%   a separate visualisation profile with non-zero bounding thicknesses.

    width = p1;

    textures = cell(1, 4);

    % texture 1: semi-infinite background (top)
    textures{1} = n_background;

    % texture 2: cap layer — square of n_cap in background
    % [cx, cy, Lx, Ly, n, shape_flag=1 for rectangle]
    textures{2} = { n_background, ...
        [0, 0, width, width, n_cap,    1] };

    % texture 3: pillar layer — square of n_pillar in background
    textures{3} = { n_background, ...
        [0, 0, width, width, n_pillar, 1] };

    % texture 4: semi-infinite substrate (bottom)
    textures{4} = n_substrate;

    % profile: layer thicknesses and texture labels, ordered top -> bottom
    profile = { [0, h_cap, height, 0], [1, 2, 3, 4] };
end
