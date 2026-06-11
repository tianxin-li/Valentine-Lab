function info = read_matfile(matpath)
% READ_MATFILE  Parse any shape library .mat file into a clean struct.
%
%   info = read_matfile(matpath)
%
%   Unified replacement for read_cross_matfile. Works for any shape written
%   by WriteMatLib. The number of geometric sweep parameters (1 or 2) is
%   read from the 'n_geom_params' field stored in the file, so no shape-
%   specific logic is needed here.
%
% -----------------------------------------------------------------------
%   OUTPUT STRUCT FIELDS
% -----------------------------------------------------------------------
%   .ok            logical   false if the file is missing or malformed
%   .msg           string    diagnostic when .ok is false
%   .path          string    input path
%
%   -- Shape identity --
%   .shape_name    string    e.g. 'cross_with_cap'
%   .shape_tag     string    e.g. 'Cross'  ('' if absent in older files)
%   .n_geom_params integer   1 or 2
%   .pol           string    'TE' or 'TM'  ('' if absent in older files)
%
%   -- Wavelength grid --
%   .wavelength    [1 x Nw]  wavelength values in micrometres
%
%   -- Geometric sweep parameters --
%   .p1_name       string    e.g. 'diameter', 'width', 'major_diameter'
%   .p1_values     [1 x Np1] sweep values for p1
%   .p2_name       string    e.g. 'aspect_ratio'  ('' for 1-param shapes)
%   .p2_values     [1 x Np2] sweep values for p2  ([] for 1-param shapes)
%
%   -- Stack constants --
%   .height        scalar    pillar height (NaN if absent)
%   .pitch         scalar    unit-cell pitch (NaN if absent)
%   .theta         scalar    incidence angle in degrees (NaN if absent)
%   .h_cap         scalar    cap thickness (NaN if absent)
%   .n_cap         scalar    cap index     (NaN if absent)
%
%   -- Materials --
%   .n_background  scalar    background index  (1 if absent)
%   .n_substrate   scalar    substrate index   (NaN if absent)
%   .n_pillar      [Nw x 1]  complex pillar index (may be scalar for
%                            non-dispersive entries)
%
%   -- Transmission / reflection data --
%   All data arrays have shape [Nw x Np1 x Np2].
%   For 1-parameter shapes Np2 = 1 (trailing singleton dimension retained
%   for uniform treatment by the table builder).
%
%   .trans_amp     [Nw x Np1 x Np2]  |amplitude| of 0-order transmission
%   .trans_phase   [Nw x Np1 x Np2]  phase of 0-order transmission (rad)
%   .trans_eff     [Nw x Np1 x Np2]  0-order transmitted power efficiency
%   .refl_eff      [Nw x Np1 x Np2]  0-order reflected power efficiency
%
%   .raw           struct    raw loaded .mat struct (for anything not
%                            unpacked here)

    % --- initialise return struct ---------------------------------------
    info      = struct();
    info.ok   = false;
    info.msg  = '';
    info.path = matpath;

    % --- existence check -----------------------------------------------
    if ~exist(matpath, 'file')
        info.msg = sprintf('File not found: %s', matpath);
        return;
    end

    % --- load -----------------------------------------------------------
    try
        raw = load(matpath);
    catch ME
        info.msg = sprintf('Failed to load: %s', ME.message);
        return;
    end
    info.raw = raw;

    % --- check required cell-array fields ------------------------------
    required = { 'param_names', 'param_values', ...
                 'constant_names', 'constant_values', ...
                 'data_names', 'data_values', ...
                 'material_names', 'material_use', 'material_index' };
    for r = 1:numel(required)
        if ~isfield(raw, required{r})
            info.msg = sprintf('Missing field "%s" in %s', required{r}, matpath);
            return;
        end
    end

    % --- shape identity -------------------------------------------------
    if isfield(raw, 'unit_cell_type')
        info.shape_name = char(raw.unit_cell_type);
    else
        info.shape_name = 'unknown';
    end

    if isfield(raw, 'shape_tag')
        info.shape_tag = char(raw.shape_tag);
    else
        info.shape_tag = '';
    end

    if isfield(raw, 'pol_saved')
        info.pol = char(raw.pol_saved);
    else
        info.pol = '';
    end

    % Determine n_geom_params: prefer the stored value, fall back to
    % inferring from how many non-wavelength params are present.
    if isfield(raw, 'n_geom_params') && ~isempty(raw.n_geom_params)
        n_geom = raw.n_geom_params;
    else
        n_non_wl = sum(~strcmpi(raw.param_names, 'wavelength'));
        n_geom   = max(1, n_non_wl);
        warning('read_matfile:noNGeomParams', ...
            'n_geom_params not stored in %s; inferred as %d.', ...
            matpath, n_geom);
    end
    info.n_geom_params = n_geom;

    % --- wavelength -----------------------------------------------------
    wl_lim = local_param(raw, 'wavelength');
    if isempty(wl_lim) || numel(wl_lim) < 3
        info.msg = 'Missing or malformed "wavelength" Param entry.';
        return;
    end
    info.wavelength = linspace(wl_lim(1), wl_lim(2), wl_lim(3));

    % --- geometric parameters ------------------------------------------
    % Find indices of non-wavelength params; order is preserved from write.
    geom_idx = find(~strcmpi(raw.param_names, 'wavelength'));

    if isempty(geom_idx)
        info.msg = 'No geometric sweep parameter found in param_names.';
        return;
    end

    % --- p1 ---
    p1_lim         = raw.param_values{geom_idx(1)};
    info.p1_name   = char(raw.param_names{geom_idx(1)});
    info.p1_values = linspace(p1_lim(1), p1_lim(2), p1_lim(3));

    % --- p2 (only for 2-parameter shapes) ---
    if n_geom == 2
        if numel(geom_idx) < 2
            info.msg = sprintf( ...
                'n_geom_params=2 but only one geometric param found in %s.', matpath);
            return;
        end
        p2_lim         = raw.param_values{geom_idx(2)};
        info.p2_name   = char(raw.param_names{geom_idx(2)});
        info.p2_values = linspace(p2_lim(1), p2_lim(2), p2_lim(3));
    else
        info.p2_name   = '';
        info.p2_values = [];
    end

    % --- constants: height / theta / h_cap / n_cap ----------------------
    info.height = local_const_scalar(raw, 'height');
    info.pitch  = local_const_scalar(raw, 'pitch');
    info.theta  = local_const_scalar(raw, 'theta');
    info.h_cap  = local_const_scalar(raw, 'h_cap');
    info.n_cap  = local_const_scalar(raw, 'n_cap');
    info.taper_mid_delta    = local_const_scalar(raw, 'taper_mid_delta');
    info.taper_bottom_delta = local_const_scalar(raw, 'taper_bottom_delta');
    info.taper_num_slices   = local_const_scalar(raw, 'taper_num_slices');

    % --- materials ------------------------------------------------------
    info.n_background = local_material(raw, 'background');
    info.n_substrate  = local_material(raw, 'substrate');
    info.n_pillar     = local_material(raw, 'pillar');

    if isempty(info.n_background), info.n_background = 1;   end
    if isempty(info.n_substrate),  info.n_substrate  = NaN; end
    if isempty(info.n_pillar),     info.n_pillar      = NaN; end

    % --- data: amplitude array and efficiency ---------------------------
    trans_raw = local_data(raw, 'transmission_bottom_0_0');
    info.trans_eff = local_data(raw, 'transmission_bottom_0_0_efficiency');
    info.refl_eff  = local_data(raw, 'reflection_bottom_0_0_efficiency');

    if isempty(trans_raw)
        info.msg = 'Missing Data field "transmission_bottom_0_0".';
        return;
    end

    % trans_raw shape: [Nw x Np1 x Np2 x 2]
    % Last dimension is [amp, phase]. Np2 = 1 for 1-param shapes.
    nd = ndims(trans_raw);
    if nd >= 4 && size(trans_raw, 4) == 2
        info.trans_amp   = trans_raw(:, :, :, 1);
        info.trans_phase = trans_raw(:, :, :, 2);
    elseif nd == 3 && size(trans_raw, 3) == 2
        % Older format: [Nw x Np1 x 2] — reshape to [Nw x Np1 x 1 x 2]
        info.trans_amp   = trans_raw(:, :, 1);
        info.trans_phase = trans_raw(:, :, 2);
        % Promote to [Nw x Np1 x 1] for uniform downstream treatment
        info.trans_amp   = reshape(info.trans_amp,   [], size(info.trans_amp,   2), 1);
        info.trans_phase = reshape(info.trans_phase, [], size(info.trans_phase, 2), 1);
    else
        % Fallback: treat as amplitude only
        info.trans_amp   = trans_raw;
        info.trans_phase = zeros(size(trans_raw));
    end

    % Efficiency fallback if not stored
    if isempty(info.trans_eff)
        info.trans_eff = info.trans_amp .^ 2;   % |t|^2 approximation
        warning('read_matfile:noEfficiency', ...
            'transmission_bottom_0_0_efficiency not found in %s; using |t|^2.', matpath);
    end
    if isempty(info.refl_eff)
        info.refl_eff = nan(size(info.trans_eff));
    end

    info.ok = true;
end

%% ===================== local helpers ==================================

function v = local_param(raw, name)
    v   = [];
    idx = find(strcmpi(raw.param_names, name), 1);
    if ~isempty(idx), v = raw.param_values{idx}; end
end

function v = local_const_scalar(raw, name)
    v   = NaN;
    idx = find(strcmpi(raw.constant_names, name), 1);
    if ~isempty(idx), v = raw.constant_values{idx}; end
    if isempty(v), v = NaN; end
end

function v = local_data(raw, name)
    v   = [];
    idx = find(strcmpi(raw.data_names, name), 1);
    if ~isempty(idx), v = raw.data_values{idx}; end
end

function v = local_material(raw, use)
    v   = [];
    idx = find(strcmpi(raw.material_use, use), 1);
    if ~isempty(idx), v = raw.material_index{idx}; end
end
