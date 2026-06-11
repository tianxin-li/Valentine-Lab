function result = fit_experimental_cross_bias(experimental_file, intended, opts)
% FIT_EXPERIMENTAL_CROSS_BIAS  Match one measured cross spectrum to fresh RCWA.
%
%   result = fit_experimental_cross_bias(experimental_file, intended)
%   result = fit_experimental_cross_bias(experimental_file, intended, opts)
%
%   The measured spectrum is assumed to be an Excel/CSV-style two-column
%   file:
%       column 1: wavelength  (um or nm; nm is auto-detected)
%       column 2: transmission (0-1 or percent; percent is auto-detected)
%
%   The function keeps pitch fixed, sweeps major width and aspect ratio
%   near the intended design, runs fresh RCWA simulations, and returns the
%   simulated geometry whose spectrum best matches the measurement. It also
%   estimates a compensated design geometry that should fabricate closer to
%   the original intended simulated spectrum, assuming the fitted bias is a
%   local process bias.
%
%   Minimal example:
%       intended = struct();
%       intended.pitch = 1.150;          % um
%       intended.width = 0.514;          % um, cross major width
%       intended.aspect_ratio = 0.20;    % minor/major
%       intended.height = 1.30;          % um
%       intended.h_cap = 0.030;          % um
%       intended.n_cap = 1.745;
%       intended.n_substrate = 1.45;
%       intended.theta = 0;              % deg
%       intended.pol = 'avg';            % 'TE', 'TM', or 'avg'
%       intended.si_file = 'D:\Rahul\Metasurface\...\Si.xlsx';
%
%       opts = struct();
%       opts.width_bias_nm = [-40 0];    % nm relative to intended.width
%       opts.ar_bias = [-0.02 0];        % relative to intended.aspect_ratio
%       result = fit_experimental_cross_bias('measured_filter.xlsx', intended, opts);
%
%   Defaults match the quick bias-estimation workflow:
%       nn                  [6 6]
%       wavelength_range    [1.00 1.65] um
%       width_step_nm       5
%       ar_step             0.01
%       scoring             RMSE + peak/dip shift, with dips weighted more

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    opts = with_defaults(opts);
    intended = validate_intended(intended);

    spec = shape_registry('cross_with_cap');
    [exp_wl, exp_t] = read_experimental_spectrum(experimental_file);
    [fit_wl, exp_fit] = prepare_fit_grid(exp_wl, exp_t, opts);
    n_pillar = load_si_index(intended.si_file, fit_wl);

    width_bias_nm = make_grid(opts.width_bias_nm(1), ...
        opts.width_bias_nm(2), opts.width_step_nm);
    ar_bias = make_grid(opts.ar_bias(1), opts.ar_bias(2), opts.ar_step);

    n_width = numel(width_bias_nm);
    n_ar = numel(ar_bias);
    n_total = n_width * n_ar;
    rows = repmat(empty_row(), n_total, 1);
    candidate_spectra = nan(numel(fit_wl), n_total);

    count = 0;

    fprintf('Fitting %s\n', input_display_name(experimental_file, opts));
    fprintf('  Pitch fixed at %.4f um, theta %.2f deg, pol %s, nn [%d %d]\n', ...
        intended.pitch, intended.theta, intended.pol, opts.nn(1), opts.nn(2));
    fprintf('  Testing %d widths x %d AR values = %d fresh RCWA spectra\n', ...
        n_width, n_ar, n_total);

    for iw = 1:n_width
        width_um = intended.width + width_bias_nm(iw) / 1000;
        if width_um <= 0
            continue;
        end

        for ia = 1:n_ar
            ar = intended.aspect_ratio + ar_bias(ia);
            if ar <= 0 || ar > 1
                continue;
            end

            count = count + 1;
            fprintf('  [%d/%d] width %.4f um (%+.0f nm), AR %.3f (%+.3f)\n', ...
                count, n_total, width_um, width_bias_nm(iw), ar, ar_bias(ia));

            sim_t = simulate_cross_spectrum(spec, fit_wl, n_pillar, ...
                intended, width_um, ar, opts);

            metrics = score_spectrum_match(fit_wl, exp_fit, sim_t, opts);
            candidate_spectra(:, count) = sim_t(:);

            rows(count).candidate_index = count;
            rows(count).width_um = width_um;
            rows(count).aspect_ratio = ar;
            rows(count).width_bias_nm = width_bias_nm(iw);
            rows(count).ar_bias = ar_bias(ia);
            rows(count).score = metrics.(opts.scoring_mode);
            rows(count).score_rmse_global_dip = metrics.score_rmse_global_dip;
            rows(count).score_global_dip_only = metrics.score_global_dip_only;
            rows(count).rmse = metrics.rmse;
            rows(count).rmse_normalized = metrics.rmse_normalized;
            rows(count).peak_shift_um = metrics.peak_shift_um;
            rows(count).dip_shift_um = metrics.dip_shift_um;
            rows(count).global_dip_exp_um = metrics.global_dip_exp_um;
            rows(count).global_dip_sim_um = metrics.global_dip_sim_um;
            rows(count).global_dip_shift_um = metrics.global_dip_shift_um;
            rows(count).scale = metrics.scale;
            rows(count).offset = metrics.offset;
        end
    end

    rows = rows(1:count);
    candidate_spectra = candidate_spectra(:, 1:count);
    table_out = struct2table(rows);
    table_out = sortrows(table_out, 'score', 'ascend');

    best = table_out(1, :);
    best_sim = candidate_spectra(:, best.candidate_index);
    selection_rmse_dip = select_candidate(table_out, candidate_spectra, ...
        intended, 'score_rmse_global_dip');
    selection_dip_only = select_candidate(table_out, candidate_spectra, ...
        intended, 'score_global_dip_only');
    compensation = estimate_compensation(intended, best);
    result = struct();
    result.experimental_file = experimental_file;
    result.intended = intended;
    result.options = opts;
    result.wavelength_um = fit_wl(:);
    result.experimental_transmission = exp_fit(:);
    result.best_simulated_transmission = best_sim(:);
    result.best = best;
    result.compensation = compensation;
    result.all_candidates = table_out;
    result.candidate_spectra = candidate_spectra;
    result.selection_rmse_global_dip = selection_rmse_dip;
    result.selection_global_dip_only = selection_dip_only;

    fprintf('\nBest match:\n');
    fprintf('  width = %.4f um  (bias %+g nm)\n', ...
        best.width_um, best.width_bias_nm);
    fprintf('  AR    = %.4f      (bias %+g)\n', ...
        best.aspect_ratio, best.ar_bias);
    fprintf('  score = %.4g, normalized RMSE = %.4g, global dip shift = %.4g um\n', ...
        best.score, best.rmse_normalized, best.global_dip_shift_um);
    fprintf('\nEstimated compensated design to recover the original target:\n');
    fprintf('  design width = %.4f um  (increase %+g nm from intended)\n', ...
        compensation.width_um, compensation.width_increase_nm);
    fprintf('  design AR    = %.4f      (increase %+g from intended)\n', ...
        compensation.aspect_ratio, compensation.ar_increase);

    if ~isempty(opts.output_prefix)
        write_outputs(result, opts.output_prefix);
    end

    if opts.make_plot
        plot_fit_result(result);
    end

end

function compensation = estimate_compensation(intended, best)
    fitted_width_bias_nm = best.width_bias_nm;
    fitted_ar_bias = best.ar_bias;

    compensation = struct();
    compensation.assumption = ...
        'Local fabrication bias is approximately constant near this design.';
    compensation.pitch_um = intended.pitch;
    compensation.width_um = intended.width - fitted_width_bias_nm / 1000;
    compensation.aspect_ratio = intended.aspect_ratio - fitted_ar_bias;
    compensation.width_increase_nm = -fitted_width_bias_nm;
    compensation.ar_increase = -fitted_ar_bias;
    compensation.fitted_actual_width_um = best.width_um;
    compensation.fitted_actual_aspect_ratio = best.aspect_ratio;
    compensation.fitted_width_bias_nm = fitted_width_bias_nm;
    compensation.fitted_ar_bias = fitted_ar_bias;
end

function selection = select_candidate(table_out, candidate_spectra, intended, score_col)
    ranked = sortrows(table_out, score_col, 'ascend');
    best = ranked(1, :);
    selection = struct();
    selection.score_mode = score_col;
    selection.best = best;
    selection.compensation = estimate_compensation(intended, best);
    selection.simulated_transmission = ...
        candidate_spectra(:, best.candidate_index);
end

function opts = with_defaults(opts)
    opts.nn = get_opt(opts, 'nn', [6 6]);
    opts.wavelength_range = get_opt(opts, 'wavelength_range', [1.00 1.65]);
    opts.max_wavelength_points = get_opt(opts, 'max_wavelength_points', 120);
    opts.width_bias_nm = get_opt(opts, 'width_bias_nm', [-40 0]);
    opts.width_step_nm = get_opt(opts, 'width_step_nm', 5);
    opts.ar_bias = get_opt(opts, 'ar_bias', [-0.02 0]);
    opts.ar_step = get_opt(opts, 'ar_step', 0.01);
    opts.n_background = get_opt(opts, 'n_background', 1);
    opts.rmse_weight = get_opt(opts, 'rmse_weight', 1.0);
    opts.peak_shift_weight = get_opt(opts, 'peak_shift_weight', 0.25);
    opts.dip_shift_weight = get_opt(opts, 'dip_shift_weight', 0.75);
    opts.global_dip_shift_weight = get_opt(opts, 'global_dip_shift_weight', 3.0);
    opts.scoring_mode = get_opt(opts, 'scoring_mode', 'score_rmse_global_dip');
    opts.max_features = get_opt(opts, 'max_features', 3);
    opts.smooth_window = get_opt(opts, 'smooth_window', 5);
    opts.amplitude_mode = get_opt(opts, 'amplitude_mode', 'affine');
    opts.make_plot = get_opt(opts, 'make_plot', true);
    opts.output_prefix = get_opt(opts, 'output_prefix', '');
    opts.display_name = get_opt(opts, 'display_name', '');

    allowed_modes = {'score_rmse_global_dip', 'score_global_dip_only'};
    if ~any(strcmp(opts.scoring_mode, allowed_modes))
        error('fit_experimental_cross_bias:badScoringMode', ...
            'opts.scoring_mode must be score_rmse_global_dip or score_global_dip_only.');
    end
end

function val = get_opt(s, name, default_val)
    if isfield(s, name) && ~isempty(s.(name))
        val = s.(name);
    else
        val = default_val;
    end
end

function label = input_display_name(experimental_input, opts)
    if ~isempty(opts.display_name)
        label = opts.display_name;
    elseif ischar(experimental_input) || isstring(experimental_input)
        label = char(string(experimental_input));
    else
        label = 'numeric experimental spectrum';
    end
end

function intended = validate_intended(intended)
    required = {'pitch', 'width', 'aspect_ratio', 'height', ...
        'h_cap', 'n_cap', 'n_substrate', 'si_file'};
    for ii = 1:numel(required)
        if ~isfield(intended, required{ii}) || isempty(intended.(required{ii}))
            error('fit_experimental_cross_bias:missingInput', ...
                'intended.%s is required.', required{ii});
        end
    end
    if ~isfield(intended, 'theta') || isempty(intended.theta)
        intended.theta = 0;
    end
    if ~isfield(intended, 'pol') || isempty(intended.pol)
        intended.pol = 'avg';
    end
    intended.pol = lower(string(intended.pol));
end

function [wl, t] = read_experimental_spectrum(filename)
    if isnumeric(filename)
        raw = filename;
    elseif isstruct(filename)
        raw = [filename.wavelength(:), filename.transmission(:)];
    else
        raw = readmatrix(filename);
    end
    if size(raw, 2) < 2
        error('fit_experimental_cross_bias:badExperimentalFile', ...
            'Experimental file must have wavelength in column 1 and transmission in column 2.');
    end

    wl = raw(:, 1);
    t = raw(:, 2);
    good = isfinite(wl) & isfinite(t);
    wl = wl(good);
    t = t(good);

    if isempty(wl)
        error('fit_experimental_cross_bias:noExperimentalData', ...
            'No numeric wavelength/transmission rows found in %s.', filename);
    end

    if median(wl) > 10
        wl = wl / 1000;
    end
    if max(t) > 2
        t = t / 100;
    end

    [wl, order] = sort(wl(:));
    t = t(order);
    [wl, unique_idx] = unique(wl, 'stable');
    t = t(unique_idx);
end

function [fit_wl, exp_fit] = prepare_fit_grid(exp_wl, exp_t, opts)
    in_band = exp_wl >= opts.wavelength_range(1) & ...
        exp_wl <= opts.wavelength_range(2);
    if nnz(in_band) < 3
        error('fit_experimental_cross_bias:noBandOverlap', ...
            'Experimental spectrum has fewer than 3 points in %.3f-%.3f um.', ...
            opts.wavelength_range(1), opts.wavelength_range(2));
    end

    wl_band = exp_wl(in_band);
    t_band = exp_t(in_band);
    n_fit = min(numel(wl_band), opts.max_wavelength_points);
    fit_wl = linspace(max(opts.wavelength_range(1), min(wl_band)), ...
        min(opts.wavelength_range(2), max(wl_band)), n_fit);
    exp_fit = interp1(wl_band, t_band, fit_wl, 'pchip');
    exp_fit = exp_fit(:).';
end

function n_pillar = load_si_index(si_file, wavelengths)
    if ~exist(si_file, 'file')
        error('fit_experimental_cross_bias:missingSiFile', ...
            'Si file not found: %s', si_file);
    end

    d = readtable(si_file);
    raw_wl = d.wl(:).';
    raw_n = (d.n(:) + 1j * d.k(:)).';
    if min(wavelengths) < min(raw_wl) || max(wavelengths) > max(raw_wl)
        error('fit_experimental_cross_bias:siRange', ...
            'Fit range %.3f-%.3f um is outside Si file range %.3f-%.3f um.', ...
            min(wavelengths), max(wavelengths), min(raw_wl), max(raw_wl));
    end
    n_pillar = interp1(raw_wl, raw_n, wavelengths, 'pchip');
end

function vals = make_grid(vmin, vmax, step)
    if step <= 0
        error('fit_experimental_cross_bias:badStep', 'Grid step must be positive.');
    end
    if vmin > vmax
        tmp = vmin; vmin = vmax; vmax = tmp;
    end
    vals = vmin:step:vmax;
    if isempty(vals) || abs(vals(end) - vmax) > 1e-12
        vals = [vals, vmax];
    end
    vals = unique(round(vals * 1e12) / 1e12, 'stable');
end

function sim_t = simulate_cross_spectrum(spec, wavelengths, n_pillar, ...
        intended, width_um, ar, opts)
    sim_t = zeros(size(wavelengths));
    for kk = 1:numel(wavelengths)
        switch intended.pol
            case "te"
                pols = 1;
            case "tm"
                pols = -1;
            otherwise
                pols = [1 -1];
        end

        vals = zeros(1, numel(pols));
        for pp = 1:numel(pols)
            [~, ~, te, ~] = RCWA_solve(spec, wavelengths(kk), ...
                intended.height, intended.n_substrate, n_pillar(kk), ...
                opts.n_background, intended.n_cap, intended.theta, ...
                intended.pitch, width_um, ar, intended.h_cap, ...
                pols(pp), opts.nn);
            vals(pp) = te;
        end
        sim_t(kk) = mean(vals);
    end
end

function metrics = score_spectrum_match(wavelengths, exp_t, sim_t, opts)
    exp_s = smooth_vec(exp_t, opts.smooth_window);
    sim_s = smooth_vec(sim_t, opts.smooth_window);

    [sim_for_rmse, scale, offset] = align_amplitude(exp_s, sim_s, opts);
    rmse = sqrt(mean((exp_s - sim_for_rmse).^2, 'omitnan'));
    denom = max(max(exp_s) - min(exp_s), 1e-6);
    rmse_norm = rmse / denom;

    exp_peaks = feature_positions(wavelengths, exp_s, 'peak', opts.max_features);
    sim_peaks = feature_positions(wavelengths, sim_s, 'peak', opts.max_features);
    exp_dips = feature_positions(wavelengths, exp_s, 'dip', opts.max_features);
    sim_dips = feature_positions(wavelengths, sim_s, 'dip', opts.max_features);

    peak_shift = nearest_feature_shift(exp_peaks, sim_peaks);
    dip_shift = nearest_feature_shift(exp_dips, sim_dips);
    band_width = max(wavelengths) - min(wavelengths);
    [~, exp_min_idx] = min(exp_s);
    [~, sim_min_idx] = min(sim_s);
    global_dip_exp_um = wavelengths(exp_min_idx);
    global_dip_sim_um = wavelengths(sim_min_idx);
    global_dip_shift_um = abs(global_dip_sim_um - global_dip_exp_um);

    local_feature_score = opts.peak_shift_weight * peak_shift / band_width + ...
        opts.dip_shift_weight * dip_shift / band_width;
    score_rmse_global_dip = opts.rmse_weight * rmse_norm + ...
        opts.global_dip_shift_weight * global_dip_shift_um / band_width;
    score_global_dip_only = global_dip_shift_um / band_width + ...
        1e-3 * rmse_norm;
    score_legacy = opts.rmse_weight * rmse_norm + ...
        opts.peak_shift_weight * peak_shift / band_width + ...
        opts.dip_shift_weight * dip_shift / band_width;

    metrics = struct();
    metrics.score_rmse_global_dip = score_rmse_global_dip;
    metrics.score_global_dip_only = score_global_dip_only;
    metrics.score_legacy_local_features = score_legacy;
    metrics.local_feature_score = local_feature_score;
    metrics.rmse = rmse;
    metrics.rmse_normalized = rmse_norm;
    metrics.peak_shift_um = peak_shift;
    metrics.dip_shift_um = dip_shift;
    metrics.global_dip_exp_um = global_dip_exp_um;
    metrics.global_dip_sim_um = global_dip_sim_um;
    metrics.global_dip_shift_um = global_dip_shift_um;
    metrics.scale = scale;
    metrics.offset = offset;
end

function y = smooth_vec(x, window)
    if window <= 1
        y = x;
    else
        y = movmean(x, window, 'omitnan');
    end
end

function [sim_aligned, scale, offset] = align_amplitude(exp_t, sim_t, opts)
    switch lower(string(opts.amplitude_mode))
        case "affine"
            A = [sim_t(:), ones(numel(sim_t), 1)];
            coeff = A \ exp_t(:);
            scale = coeff(1);
            offset = coeff(2);
            sim_aligned = (scale * sim_t + offset);
        case "none"
            scale = 1;
            offset = 0;
            sim_aligned = sim_t;
        otherwise
            error('fit_experimental_cross_bias:badAmplitudeMode', ...
                'opts.amplitude_mode must be ''affine'' or ''none''.');
    end
end

function locs = feature_positions(wavelengths, y, kind, max_features)
    y = y(:).';
    wavelengths = wavelengths(:).';
    if numel(y) < 3
        locs = wavelengths;
        return;
    end

    switch kind
        case 'peak'
            idx = find(y(2:end-1) >= y(1:end-2) & ...
                y(2:end-1) >= y(3:end)) + 1;
            if isempty(idx)
                [~, idx] = max(y);
            else
                [~, order] = sort(y(idx), 'descend');
                idx = idx(order);
            end
        case 'dip'
            idx = find(y(2:end-1) <= y(1:end-2) & ...
                y(2:end-1) <= y(3:end)) + 1;
            if isempty(idx)
                [~, idx] = min(y);
            else
                [~, order] = sort(y(idx), 'ascend');
                idx = idx(order);
            end
        otherwise
            error('fit_experimental_cross_bias:badFeatureKind', ...
                'Feature kind must be peak or dip.');
    end

    idx = idx(1:min(max_features, numel(idx)));
    locs = sort(wavelengths(idx));
end

function shift = nearest_feature_shift(exp_locs, sim_locs)
    if isempty(exp_locs) || isempty(sim_locs)
        shift = inf;
        return;
    end
    diffs = zeros(size(exp_locs));
    for ii = 1:numel(exp_locs)
        diffs(ii) = min(abs(sim_locs - exp_locs(ii)));
    end
    shift = mean(diffs, 'omitnan');
end

function row = empty_row()
    row = struct( ...
        'candidate_index', NaN, ...
        'width_um', NaN, ...
        'aspect_ratio', NaN, ...
        'width_bias_nm', NaN, ...
        'ar_bias', NaN, ...
        'score', NaN, ...
        'score_rmse_global_dip', NaN, ...
        'score_global_dip_only', NaN, ...
        'rmse', NaN, ...
        'rmse_normalized', NaN, ...
        'peak_shift_um', NaN, ...
        'dip_shift_um', NaN, ...
        'global_dip_exp_um', NaN, ...
        'global_dip_sim_um', NaN, ...
        'global_dip_shift_um', NaN, ...
        'scale', NaN, ...
        'offset', NaN);
end

function write_outputs(result, output_prefix)
    writetable(result.all_candidates, [output_prefix '_candidates.xlsx']);
    T = table(result.wavelength_um, result.experimental_transmission, ...
        result.best_simulated_transmission, ...
        'VariableNames', {'wavelength_um', 'experimental', 'best_simulated'});
    writetable(T, [output_prefix '_best_spectrum.xlsx']);
end

function plot_fit_result(result)
    figure('Name', 'Experimental Cross Bias Fit');
    plot(result.wavelength_um, result.experimental_transmission, ...
        'LineWidth', 2.0, 'DisplayName', 'Experimental');
    hold on;
    plot(result.wavelength_um, result.best_simulated_transmission, ...
        'LineWidth', 2.0, 'DisplayName', 'Best simulated');
    xline(result.best.global_dip_exp_um, '--', ...
        'DisplayName', 'Experimental global dip');
    xline(result.best.global_dip_sim_um, ':', ...
        'DisplayName', 'Simulated global dip');
    grid on;
    xlabel('Wavelength (um)');
    ylabel('Transmission');
    title(sprintf('Best fit: width %.4f um (%+.0f nm), AR %.3f (%+.3f)', ...
        result.best.width_um, result.best.width_bias_nm, ...
        result.best.aspect_ratio, result.best.ar_bias));
    legend('Location', 'best');
end
