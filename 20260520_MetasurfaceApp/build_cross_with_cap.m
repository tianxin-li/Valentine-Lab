function [textures, profile] = build_cross_with_cap(n_background, n_pillar, ...
        n_cap, n_substrate, p1, p2, h_cap, height)
% BUILD_CROSS_WITH_CAP  RETICOLO geometry for a cross-shaped pillar with cap.
%
%   [textures, profile] = build_cross_with_cap(n_background, n_pillar,
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
%       p1           : major arm width  w1  (the long dimension of each arm)
%       p2           : aspect ratio = w2 / w1  (0 < p2 <= 1)
%                      minor arm width w2 = p1 * p2
%       h_cap        : thickness of the cap layer
%       height       : thickness of the pillar layer
%
%   OUTPUTS
%       textures : 1x4 cell array for RETICOLO res1()
%       profile  : RETICOLO profile cell array for res2() / res3()
%
%   LAYER STACK (top -> bottom, matching profile order):
%       texture 1 : uniform background (air)            thickness 0
%       texture 2 : cap cross    (n_cap)                thickness h_cap
%       texture 3 : pillar cross (n_pillar)              thickness height
%       texture 4 : uniform substrate                   thickness 0
%
%   The cross is formed by two overlapping rectangles centred at (0,0):
%       arm A: w1 (x-extent) by w2 (y-extent)   — horizontal arm
%       arm B: w2 (x-extent) by w1 (y-extent)   — vertical arm
%   RETICOLO's last-inclusion-wins overlap rule means the intersection
%   region gets n_pillar (or n_cap), which is correct since both arms
%   are the same material.
%
%   NOTE on version history:
%   Previous versions of this file accepted absolute w2 as the second
%   geometric argument. The unified pipeline passes aspect ratio (p2) and
%   computes w2 = p1 * p2 here so all builders share an identical signature.
%   If you have older code that passes absolute w2 directly, update those
%   call sites or keep a separate legacy wrapper.
%
%   NOTE: top and bottom bounding layers carry zero thickness because they
%   are physically semi-infinite. For field visualisation with res3, use
%   a separate visualisation profile with non-zero bounding thicknesses.

    w1 = p1;
    w2 = p1 * p2;   % minor arm width = major width * aspect ratio

    textures = cell(1, 4);

    % texture 1: semi-infinite background (top)
    textures{1} = n_background;

    % texture 2: cap layer — cross of n_cap in background
    % Two overlapping rectangles; trailing 1 = rectangle shape flag
    textures{2} = { n_background, ...
        [0, 0, w1, w2, n_cap, 1], ...   % horizontal arm
        [0, 0, w2, w1, n_cap, 1] };     % vertical arm

    % texture 3: pillar layer — cross of n_pillar in background
    textures{3} = { n_background, ...
        [0, 0, w1, w2, n_pillar, 1], ...
        [0, 0, w2, w1, n_pillar, 1] };

    % texture 4: semi-infinite substrate (bottom)
    textures{4} = n_substrate;

    % profile: layer thicknesses and texture labels, ordered top -> bottom
    profile = { [0, h_cap, height, 0], [1, 2, 3, 4] };
end
