function [textures, profile] = build_tapered_cross_with_cap(n_background, n_pillar, ...
        n_cap, n_substrate, p1, p2, h_cap, height, opts)
% BUILD_TAPERED_CROSS_WITH_CAP  Staircased tapered cross RETICOLO geometry.
%
%   [textures, profile] = build_tapered_cross_with_cap(n_background,
%       n_pillar, n_cap, n_substrate, p1, p2, h_cap, height, opts)
%
%   p1 is the top major width. p2 is a fixed aspect ratio used at every
%   vertical slice. The middle and bottom major widths are p1 plus the
%   optional deltas in opts:
%       mid_width    = p1 + opts.taper_mid_delta
%       bottom_width = p1 + opts.taper_bottom_delta
%
%   Negative deltas are valid and represent narrowing toward the bottom.

    if nargin < 9 || isempty(opts)
        opts = struct();
    end

    taper_mid_delta = opt_scalar(opts, 'taper_mid_delta', 0);
    taper_bottom_delta = opt_scalar(opts, 'taper_bottom_delta', 0);
    n_slices = round(opt_scalar(opts, 'taper_num_slices', 6));
    n_slices = max(2, n_slices);

    top_w = p1;
    mid_w = p1 + taper_mid_delta;
    bottom_w = p1 + taper_bottom_delta;

    if top_w <= 0 || mid_w <= 0 || bottom_w <= 0
        error('build_tapered_cross_with_cap:badWidth', ...
            ['Tapered cross widths must be positive. Got top %.4g, ' ...
            'middle %.4g, bottom %.4g um.'], top_w, mid_w, bottom_w);
    end
    if p2 <= 0 || p2 > 1
        error('build_tapered_cross_with_cap:badAR', ...
            'Aspect ratio must be in (0, 1]. Got %.4g.', p2);
    end

    widths_top_to_bottom = tapered_widths(top_w, mid_w, bottom_w, n_slices);
    widths_profile_order = widths_top_to_bottom;

    textures = cell(1, n_slices + 3);
    textures{1} = n_background;

    % Cap uses the top surface dimensions.
    textures{2} = cross_texture(n_background, n_cap, top_w, top_w * p2);

    for ii = 1:n_slices
        w1 = widths_profile_order(ii);
        w2 = w1 * p2;
        if w2 <= 0
            error('build_tapered_cross_with_cap:badMinorWidth', ...
                'Minor width must be positive. Slice %d gave %.4g um.', ii, w2);
        end
        textures{ii + 2} = cross_texture(n_background, n_pillar, w1, w2);
    end

    textures{end} = n_substrate;

    slice_h = height / n_slices;
    profile = { [0, h_cap, repmat(slice_h, 1, n_slices), 0], ...
                1:(n_slices + 3) };
end

function tex = cross_texture(n_background, n_material, w1, w2)
    tex = { n_background, ...
        [0, 0, w1, w2, n_material, 1], ...
        [0, 0, w2, w1, n_material, 1] };
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
