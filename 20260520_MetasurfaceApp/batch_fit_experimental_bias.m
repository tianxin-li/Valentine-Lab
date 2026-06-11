function summary = batch_fit_experimental_bias(experimental_file, geometry_file, common, opts)
% BATCH_FIT_EXPERIMENTAL_BIAS  Overnight batch fitting for measured filters.
%
%   summary = batch_fit_experimental_bias(experimental_file, geometry_file,
%       common, opts)
%
% Experimental file:
%   Row 1 headers: wl, 11, 21, 31, ...
%   Column 1: wavelength
%   Columns 2+: measured filter transmissions
%
% Geometry file:
%   One geometry label per row. Row 1 maps to experimental column 2, row 2
%   maps to experimental column 3, etc.
%
% Outputs are written to:
%   opts.output_root/RMSE_plus_global_dip
%   opts.output_root/Global_dip_only
%
% The RCWA candidate sweep is run once per filter and checkpointed in
% opts.output_root/per_filter_checkpoints.

    if nargin < 4 || isempty(opts)
        opts = struct();
    end
    opts = batch_defaults(opts);
    common = common_defaults(common);

    ensure_dir(opts.output_root);
    checkpoint_dir = fullfile(opts.output_root, 'per_filter_checkpoints');
    ensure_dir(checkpoint_dir);

    modes = mode_configs();
    for mi = 1:numel(modes)
        ensure_dir(fullfile(opts.output_root, modes(mi).folder));
        ensure_dir(fullfile(opts.output_root, modes(mi).folder, 'plots'));
        ensure_dir(fullfile(opts.output_root, modes(mi).folder, 'spectra'));
    end

    [wl, spectra, filter_ids] = read_experimental_table(experimental_file);
    geometry_names = read_geometry_list(geometry_file);
    n_filters = min(numel(filter_ids), numel(geometry_names));
    if n_filters < numel(filter_ids)
        warning('batch_fit:geometryCount', ...
            'Only %d geometry rows found for %d experimental filters.', ...
            n_filters, numel(filter_ids));
    end

    all_rows = repmat(summary_empty_row(), n_filters, numel(modes));

    fprintf('Batch fitting %d filters. Output root:\n  %s\n', ...
        n_filters, opts.output_root);

    for fi = 1:n_filters
        filter_id = sanitize_id(filter_ids{fi});
        geom = parse_filter_geometry_name(geometry_names{fi});
        ckpt_path = fullfile(checkpoint_dir, sprintf('Filter_%s_result.mat', filter_id));

        if opts.resume && exist(ckpt_path, 'file')
            fprintf('[SKIP] Filter %s already checkpointed.\n', filter_id);
            S = load(ckpt_path, 'filter_result');
            filter_result = S.filter_result;
        else
            fprintf('\n===== Filter %s (%d / %d) =====\n', filter_id, fi, n_filters);
            filter_result = run_one_filter(wl, spectra(:, fi), filter_ids{fi}, ...
                geometry_names{fi}, geom, common, opts);
            save(ckpt_path, 'filter_result');
        end

        for mi = 1:numel(modes)
            row = make_summary_row(filter_result, modes(mi));
            all_rows(fi, mi) = row;
            write_mode_outputs(filter_result, modes(mi), opts);
        end

        write_all_summaries(all_rows, modes, opts);
    end

    summary = write_all_summaries(all_rows, modes, opts);
    fprintf('\nBatch complete.\n');
end

function filter_result = run_one_filter(wl, t, filter_id, geometry_name, geom, common, opts)
    filter_result = struct();
    filter_result.filter_id = char(string(filter_id));
    filter_result.geometry_name = char(string(geometry_name));
    filter_result.geometry = geom;
    filter_result.status = "ok";
    filter_result.message = "";
    filter_result.fit = [];

    if geom.shape ~= "cross"
        filter_result.status = "skipped";
        filter_result.message = "Only cross filters are fitted in this batch version.";
        fprintf('  Skipping %s geometry: %s\n', geom.shape, geometry_name);
        return;
    end

    try
        intended = struct();
        intended.pitch = geom.pitch;
        intended.width = geom.width;
        intended.aspect_ratio = geom.aspect_ratio;
        intended.height = geom.height;
        intended.h_cap = common.h_cap;
        intended.n_cap = common.n_cap;
        intended.n_substrate = common.n_substrate;
        intended.theta = common.theta;
        intended.pol = common.pol;
        intended.si_file = common.si_file;

        fit_opts = opts.fit;
        fit_opts.make_plot = false;
        fit_opts.output_prefix = '';
        fit_opts.scoring_mode = 'score_rmse_global_dip';
        fit_opts.display_name = sprintf('Filter %s', char(string(filter_id)));

        filter_result.fit = fit_experimental_cross_bias([wl(:), t(:)], ...
            intended, fit_opts);
    catch ME
        filter_result.status = "error";
        filter_result.message = ME.message;
        fprintf('  ERROR: %s\n', ME.message);
    end
end

function write_mode_outputs(filter_result, mode, opts)
    mode_dir = fullfile(opts.output_root, mode.folder);
    plots_dir = fullfile(mode_dir, 'plots');
    spectra_dir = fullfile(mode_dir, 'spectra');
    filter_id = sanitize_id(filter_result.filter_id);

    if filter_result.status ~= "ok"
        return;
    end

    selection = get_selection(filter_result.fit, mode.score_field);
    best = selection.best;
    spec_table = table(filter_result.fit.wavelength_um, ...
        filter_result.fit.experimental_transmission, ...
        selection.simulated_transmission(:), ...
        'VariableNames', {'wavelength_um', 'experimental', 'best_simulated'});
    writetable(spec_table, fullfile(spectra_dir, ...
        sprintf('Filter_%s_best_spectrum.xlsx', filter_id)));

    fig = figure('Visible', 'off', 'Name', sprintf('Filter %s %s', ...
        filter_result.filter_id, mode.label));
    plot(filter_result.fit.wavelength_um, ...
        filter_result.fit.experimental_transmission, ...
        'LineWidth', 2.0, 'DisplayName', 'Experimental');
    hold on;
    plot(filter_result.fit.wavelength_um, ...
        selection.simulated_transmission, ...
        'LineWidth', 2.0, 'DisplayName', 'Best simulated');
    xline(best.global_dip_exp_um, '--', ...
        'DisplayName', 'Experimental global dip');
    xline(best.global_dip_sim_um, ':', ...
        'DisplayName', 'Simulated global dip');
    grid on;
    xlabel('Wavelength (um)');
    ylabel('Transmission');
    title(sprintf('Filter %s - %s', filter_result.filter_id, mode.label), ...
        'Interpreter', 'none');
    legend('Location', 'best');
    saveas(fig, fullfile(plots_dir, sprintf('Filter_%s_fit.png', filter_id)));
    close(fig);
end

function summary = write_all_summaries(all_rows, modes, opts)
    summary = struct();
    for mi = 1:numel(modes)
        rows = all_rows(:, mi);
        T = struct2table(rows);
        out_path = fullfile(opts.output_root, modes(mi).folder, 'summary.xlsx');
        writetable(T, out_path);
        summary.(modes(mi).name) = T;
    end
end

function row = make_summary_row(filter_result, mode)
    row = summary_empty_row();
    row.FilterID = string(filter_result.filter_id);
    row.GeometryName = string(filter_result.geometry_name);
    row.Shape = string(filter_result.geometry.shape);
    row.Status = string(filter_result.status);
    row.Message = string(filter_result.message);

    geom = filter_result.geometry;
    row.Intended_Height_um = geom.height;
    row.Intended_Pitch_um = geom.pitch;
    row.Intended_Width_um = geom.width;
    row.Intended_AR = geom.aspect_ratio;

    if filter_result.status ~= "ok"
        return;
    end

    selection = get_selection(filter_result.fit, mode.score_field);
    best = selection.best;
    comp = selection.compensation;

    row.BestFit_Width_um = best.width_um;
    row.BestFit_AR = best.aspect_ratio;
    row.Width_Bias_nm = best.width_bias_nm;
    row.AR_Bias = best.ar_bias;
    row.Compensated_Width_um = comp.width_um;
    row.Compensated_AR = comp.aspect_ratio;
    row.Recommended_Width_Increase_nm = comp.width_increase_nm;
    row.Recommended_AR_Increase = comp.ar_increase;
    row.Experimental_Global_Dip_um = best.global_dip_exp_um;
    row.BestSim_Global_Dip_um = best.global_dip_sim_um;
    row.Global_Dip_Shift_um = best.global_dip_shift_um;
    row.RMSE = best.rmse;
    row.Normalized_RMSE = best.rmse_normalized;
    row.Score = best.(mode.score_field);
end

function selection = get_selection(fit, score_field)
    switch score_field
        case 'score_rmse_global_dip'
            selection = fit.selection_rmse_global_dip;
        case 'score_global_dip_only'
            selection = fit.selection_global_dip_only;
        otherwise
            error('batch_fit:badMode', 'Unknown score field %s.', score_field);
    end
end

function [wl, spectra, ids] = read_experimental_table(filename)
    C = readcell(filename);
    headers = C(1, :);
    ids = cell(1, size(C, 2) - 1);
    for jj = 2:size(C, 2)
        ids{jj - 1} = char(string(headers{jj}));
    end

    data = cell_to_numeric(C(2:end, :));
    wl = data(:, 1);
    spectra = data(:, 2:end);
    good = isfinite(wl);
    wl = wl(good);
    spectra = spectra(good, :);
    if median(wl, 'omitnan') > 10
        wl = wl / 1000;
    end
    if max(spectra(:), [], 'omitnan') > 2
        spectra = spectra / 100;
    end
end

function geometry_names = read_geometry_list(filename)
    C = readcell(filename);
    C = C(:);
    geometry_names = {};
    for ii = 1:numel(C)
        if ismissing_cell(C{ii})
            continue;
        end
        txt = char(string(C{ii}));
        if contains(txt, 'Height_', 'IgnoreCase', true)
            geometry_names{end+1} = txt; %#ok<AGROW>
        end
    end
end

function M = cell_to_numeric(C)
    M = nan(size(C));
    for ii = 1:numel(C)
        if isnumeric(C{ii})
            M(ii) = C{ii};
        elseif ischar(C{ii}) || isstring(C{ii})
            M(ii) = str2double(string(C{ii}));
        end
    end
end

function tf = ismissing_cell(x)
    tf = isempty(x) || (isstring(x) && strlength(x) == 0) || ...
        (ischar(x) && isempty(strtrim(x))) || ...
        (isnumeric(x) && all(isnan(x)));
end

function common = common_defaults(common)
    required = {'si_file', 'h_cap', 'n_cap', 'n_substrate'};
    for ii = 1:numel(required)
        if ~isfield(common, required{ii}) || isempty(common.(required{ii}))
            error('batch_fit:missingCommon', 'common.%s is required.', required{ii});
        end
    end
    if ~isfield(common, 'theta') || isempty(common.theta)
        common.theta = 0;
    end
    if ~isfield(common, 'pol') || isempty(common.pol)
        common.pol = 'avg';
    end
end

function opts = batch_defaults(opts)
    opts.output_root = get_opt(opts, 'output_root', ...
        fullfile(pwd, ['BiasFit_' char(datetime('now', ...
        'Format', 'yyyyMMdd_HHmmss'))]));
    opts.resume = get_opt(opts, 'resume', true);
    if ~isfield(opts, 'fit') || isempty(opts.fit)
        opts.fit = struct();
    end
    opts.fit.nn = get_opt(opts.fit, 'nn', [6 6]);
    opts.fit.wavelength_range = get_opt(opts.fit, 'wavelength_range', [1.00 1.65]);
    opts.fit.width_bias_nm = get_opt(opts.fit, 'width_bias_nm', [-40 0]);
    opts.fit.width_step_nm = get_opt(opts.fit, 'width_step_nm', 5);
    opts.fit.ar_bias = get_opt(opts.fit, 'ar_bias', [-0.02 0]);
    opts.fit.ar_step = get_opt(opts.fit, 'ar_step', 0.01);
    opts.fit.global_dip_shift_weight = get_opt(opts.fit, ...
        'global_dip_shift_weight', 3.0);
    opts.fit.rmse_weight = get_opt(opts.fit, 'rmse_weight', 1.0);
end

function modes = mode_configs()
    modes = struct( ...
        'name', {'rmse_plus_global_dip', 'global_dip_only'}, ...
        'folder', {'RMSE_plus_global_dip', 'Global_dip_only'}, ...
        'label', {'RMSE + global dip', 'Global dip only'}, ...
        'score_field', {'score_rmse_global_dip', 'score_global_dip_only'});
end

function row = summary_empty_row()
    row = struct( ...
        'FilterID', "", ...
        'GeometryName', "", ...
        'Shape', "", ...
        'Status', "", ...
        'Message', "", ...
        'Intended_Height_um', NaN, ...
        'Intended_Pitch_um', NaN, ...
        'Intended_Width_um', NaN, ...
        'Intended_AR', NaN, ...
        'BestFit_Width_um', NaN, ...
        'BestFit_AR', NaN, ...
        'Width_Bias_nm', NaN, ...
        'AR_Bias', NaN, ...
        'Compensated_Width_um', NaN, ...
        'Compensated_AR', NaN, ...
        'Recommended_Width_Increase_nm', NaN, ...
        'Recommended_AR_Increase', NaN, ...
        'Experimental_Global_Dip_um', NaN, ...
        'BestSim_Global_Dip_um', NaN, ...
        'Global_Dip_Shift_um', NaN, ...
        'RMSE', NaN, ...
        'Normalized_RMSE', NaN, ...
        'Score', NaN);
end

function id = sanitize_id(id_in)
    id = char(string(id_in));
    id = regexprep(id, '[^\w.-]', '_');
end

function ensure_dir(pathname)
    if ~exist(pathname, 'dir')
        mkdir(pathname);
    end
end

function val = get_opt(s, name, default_val)
    if isfield(s, name) && ~isempty(s.(name))
        val = s.(name);
    else
        val = default_val;
    end
end
