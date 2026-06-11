function [textures, profile] = build_tapered_circle_with_cap(n_background, n_pillar, ...
        n_cap, n_substrate, p1, ~, h_cap, height, opts)
% BUILD_TAPERED_CIRCLE_WITH_CAP  Staircased tapered circular pillar.
%
%   p1 is the top diameter. The middle and bottom diameters are p1 plus
%   optional deltas in opts:
%       mid_diameter    = p1 + opts.taper_mid_delta
%       bottom_diameter = p1 + opts.taper_bottom_delta
%
%   Negative deltas are valid and represent narrowing toward the bottom.

    if nargin < 9 || isempty(opts)
        opts = struct();
    end

    taper_mid_delta = opt_scalar(opts, 'taper_mid_delta', 0);
    taper_bottom_delta = opt_scalar(opts, 'taper_bottom_delta', 0);
    n_slices = round(opt_scalar(opts, 'taper_num_slices', 6));
    n_slices = max(2, n_slices);

    top_d = p1;
    mid_d = p1 + taper_mid_delta;
    bottom_d = p1 + taper_bottom_delta;

    if top_d <= 0 || mid_d <= 0 || bottom_d <= 0
        error('build_tapered_circle_with_cap:badDiameter', ...
            ['Tapered circle diameters must be positive. Got top %.4g, ' ...
            'middle %.4g, bottom %.4g um.'], top_d, mid_d, bottom_d);
    end

    diameters_top_to_bottom = tapered_widths(top_d, mid_d, bottom_d, n_slices);
    n_staircase = 36;

    textures = cell(1, n_slices + 3);
    textures{1} = n_background;

    % Cap uses the top surface diameter.
    textures{2} = circle_texture(n_background, n_cap, top_d, n_staircase);

    for ii = 1:n_slices
        d = diameters_top_to_bottom(ii);
        textures{ii + 2} = circle_texture(n_background, n_pillar, d, n_staircase);
    end

    textures{end} = n_substrate;

    slice_h = height / n_slices;
    profile = { [0, h_cap, repmat(slice_h, 1, n_slices), 0], ...
                1:(n_slices + 3) };
end

function tex = circle_texture(n_background, n_material, diameter, n_staircase)
    tex = { n_background, ...
        [0, 0, diameter, diameter, n_material, n_staircase] };
end

function widths = tapered_widths(top_w, mid_w, bottom_w, n_slices)
    if n_slices == 2
        widths = [top_w, bottom_w];
        return;
    end

    z = linspace(0, 1, n_slices);
    widths = zeros(1, n_slices);
    for ii = 1:n_slices
        if z(ii) <= 0.5
            a = z(ii) / 0.5;
            widths(ii) = (1 - a) * top_w + a * mid_w;
        else
            a = (z(ii) - 0.5) / 0.5;
            widths(ii) = (1 - a) * mid_w + a * bottom_w;
        end
    end
end

function val = opt_scalar(opts, name, default_val)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default_val;
    end
end
