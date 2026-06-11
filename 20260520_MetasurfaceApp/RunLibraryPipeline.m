%% RunLibraryPipeline.m
%  Unified driver for the metasurface filter library.
%  Works for any shape registered in shape_registry.
%
%  FEATURES
%   - TE and TM swept automatically
%   - Checkpoint/skip: completed .mat files are not recomputed on re-run
%   - Energy conservation log: flags higher-order diffraction and absorption
%   - Pitch stored as a Constant in every .mat file
%   - All results under one fixed timestamp folder
%
%  OUTPUT TREE
%   base_path / <pillar>_on_<substrate>_<shape> / <timestamp> /
%     TE/   Height_*/Pitch_*/*.mat + TransmissionTable_<shape>_theta*.csv
%     TM/   Height_*/Pitch_*/*.mat + TransmissionTable_<shape>_theta*.csv
%     Averaged/  TransmissionTable_<shape>_theta*.csv  <- final filter tables
%     energy_log_<timestamp>.txt                       <- energy balance report
%
%  TO ADD A NEW SHAPE: add it to shape_registry.m and write build_*.m.
%  Nothing in this script changes.

clc; clearvars; close all;

appDir     = fileparts(mfilename('fullpath'));
projectDir = fileparts(appDir);
%projectDir = 'D:\Downloads\Valentine Group Papers\For Tian'; %IF FOLDER PATH CHANGE, CHANGE THIS
% projectDir = fullfile(getenv('HOME'), 'Downloads', ...
%     'Valentine Group Papers', 'For Tian');%addpath(appDir);
rcwaDir    = fullfile(projectDir, 'RCWA functions');
fourierDir = fullfile(projectDir, 'Fourier Functions');
libraryDir = fullfile(projectDir, 'Library Data2');
if exist(rcwaDir, 'dir'),    addpath(rcwaDir);    end
if exist(fourierDir, 'dir'), addpath(fourierDir); end
if exist(libraryDir, 'dir'), addpath(libraryDir); end

%% =====================================================================
%% USER PARAMETERS
%% =====================================================================

% --- Shape ------------------------------------------------------------
% Run  shape_registry()  in the command window to see available options.
shape_name = 'circle_with_cap';

% CHRIS AND TIAN, IGNORE THIS
% Tapered-shape options. Used only when shape_name is
% 'tapered_cross_with_cap' or 'tapered_circle_with_cap'. Deltas are
% relative to the swept top width/diameter; negative values mean the
% structure narrows toward the base.
taper_mid_delta    = -0.04;  % um, middle major width = top width + delta
taper_bottom_delta = -0.113;  % um, bottom major width = top width + delta
taper_num_slices   = 30;       % vertical staircase slices through pillar

% --- Geometric sweep: Parameter 1 ------------------------------------
% circle/ellipse -> p1 = diameter / major diameter
% square         -> p1 = width
% cross          -> p1 = major arm width
min_p1 = 0.2; %normalized to pitch (i.e. min_p1 = desired_diam/pitch)
max_p1_fraction = 0.8;   % max p1 = this fraction of the current pitch
num_p1 = 4; %number of data points between min and max

% --- Geometric sweep: Parameter 2 (aspect ratio) ---------------------
% cross / ellipse -> p2 = minor/major  (ignored for circle/square)
min_p2 = 0.20;
max_p2 = 0.60;
num_p2 = 1; %9;

% --- Stack geometry ---------------------------------------------------
heights = 14.0:1.0:17.0;          % pillar height(s) in um — scalar or vector
h_cap   = 0; %0.030;        % cap layer thickness in um
pitches = 4.0:1.0:8.0;        % unit-cell pitch(es) in um — scalar or vector

% --- Materials --------------------------------------------------------
waveband           = 'LWIR';
pillar_mat_name    = 'Si';
substrate_mat_name = 'Si';
n_background       = 1;
n_substrate        = 3.41;
n_cap              = 1.745; %ignore this

% --- Wavelength window ------------------------------------------------
% Leave empty to use the full wavelength range available in material_file.
% Set both values, e.g. requested_min_wavelength = 8.00 and
% requested_max_wavelength = 14.00, to simulate a narrower band.
requested_min_wavelength = 8.00;
requested_max_wavelength = 14.00;

% --- Angles and solver ------------------------------------------------
angles = [0];
nn     = [6, 6];

% --- Energy conservation log -----------------------------------------
% When true, each RCWA call also returns total T and R (all orders).
% This adds ~5-10% overhead per wavelength but lets the log distinguish
% between higher-order diffraction and material absorption.
enable_energy_log = false;

% Thresholds for the energy log
HOE_warn_threshold  = 0.02;   % flag if HOE fraction > 2% at any wavelength
abs_warn_threshold  = 0.30;   % flag if absorbed fraction > 30% (informational)
energy_bal_tol      = 0.05;   % flag if T_total+R_total differs from expected by > 5%

% --- Output options ---------------------------------------------------
make_plots = false;

% --- Resume / checkpointing -------------------------------------------
% Leave empty to start a new timestamped run.
% Set to a previous run timestamp (for example '2026-05-19_131245') to
% resume that run and skip any .mat files that already exist.
resume_run_id = '';

% --- Paths ------------------------------------------------------------
base_path     = libraryDir; %% CHANGE THIS AND SET TO WHERE YOU WANT TO SAVE THE FILES TO
material_file = fullfile(projectDir, 'Material Dielectric Function', ...
    'Si_LWIR_8to14.xlsx');

%% =====================================================================
%% END USER PARAMETERS
%% =====================================================================

spec = shape_registry(shape_name);
if ismember(lower(spec.shape_name), {'tapered_cross_with_cap', 'tapered_circle_with_cap'})
    spec.build_options.taper_mid_delta = taper_mid_delta;
    spec.build_options.taper_bottom_delta = taper_bottom_delta;
    spec.build_options.taper_num_slices = taper_num_slices;
end
if strcmpi(spec.shape_name, 'tapered_cross_with_cap')
    spec.row_name_fn = @(h,p,p1,p2) sprintf([ ...
        'Height_%04.2f_Pitch_%.3f_TopWidth_%.3f_AR_%.2f_' ...
        'TaperMid_%+.3f_TaperBottom_%+.3f_TaperedCross'], ...
        h, p, p1, p2, taper_mid_delta, taper_bottom_delta);
elseif strcmpi(spec.shape_name, 'tapered_circle_with_cap')
    spec.row_name_fn = @(h,p,p1,~) sprintf([ ...
        'Height_%04.2f_Pitch_%.3f_TopDiameter_%.3f_' ...
        'TaperMid_%+.3f_TaperBottom_%+.3f_TaperedCircle'], ...
        h, p, p1, taper_mid_delta, taper_bottom_delta);
end
fprintf('Shape: %s  (%s)\n', spec.shape_name, spec.display_name);

% Enforce p2 = [1] for 1-parameter shapes
if spec.n_geom_params == 1
    p2_values = 1;
    num_p2    = 1;
    p2_lim    = [];
else
    p2_values = linspace(min_p2, max_p2, num_p2);
    p2_lim    = [min_p2, max_p2, num_p2];
end

% Material dispersion
if ~exist(material_file, 'file')
    error('RunLibraryPipeline:noMatFile', ...
        'Material file not found:\n  %s', material_file);
end
data            = readtable(material_file);
n_pillar_raw    = (data.n(:) + 1j * data.k(:)).';
wavelength_raw  = data.wl(:).';
file_min_wavelength = min(wavelength_raw);
file_max_wavelength = max(wavelength_raw);

if isempty(requested_min_wavelength)
    min_wavelength = file_min_wavelength;
else
    min_wavelength = requested_min_wavelength;
end
if isempty(requested_max_wavelength)
    max_wavelength = file_max_wavelength;
else
    max_wavelength = requested_max_wavelength;
end

if min_wavelength >= max_wavelength
    error('RunLibraryPipeline:badWavelengthRange', ...
        'requested_min_wavelength must be smaller than requested_max_wavelength.');
end
if min_wavelength < file_min_wavelength || max_wavelength > file_max_wavelength
    error('RunLibraryPipeline:wavelengthOutOfRange', ...
        ['Requested wavelength range %.4f-%.4f um is outside the material file ' ...
        'range %.4f-%.4f um.'], ...
        min_wavelength, max_wavelength, file_min_wavelength, file_max_wavelength);
end

in_wavelength_window = wavelength_raw >= min_wavelength & wavelength_raw <= max_wavelength;
num_wavelengths = max(2, nnz(in_wavelength_window));
wavelength     = linspace(min_wavelength, max_wavelength, num_wavelengths);
wavelength_lim = [min_wavelength, max_wavelength, num_wavelengths];
n_pillar       = interp1(wavelength_raw, n_pillar_raw, wavelength, 'pchip');

material_folder = sprintf('%s_on_%s_%s', ...
    pillar_mat_name, substrate_mat_name, spec.shape_name);

resume_run_id = strtrim(char(resume_run_id));
if isempty(resume_run_id)
    timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'));
    fprintf('Starting new run: %s\n', timestamp);
else
    timestamp = resume_run_id;
    fprintf('Resuming run: %s\n', timestamp);
end

run_root = fullfile(base_path, material_folder, timestamp);
if exist(run_root, 'file') && ~isfolder(run_root)
    error('RunLibraryPipeline:badResumePath', ...
        'Resume path exists but is not a folder:\n  %s', run_root);
end
if ~isempty(resume_run_id) && isfolder(run_root)
    has_expected_structure = isfolder(fullfile(run_root, 'TE')) || ...
        isfolder(fullfile(run_root, 'TM')) || ...
        isfolder(fullfile(run_root, 'Averaged'));
    if ~has_expected_structure
        warning('RunLibraryPipeline:resumeEmptyRunRoot', ...
            ['Resume folder exists but has no TE/TM/Averaged subfolders yet. ' ...
            'Continuing and treating it as an empty compatible run:\n  %s'], ...
            run_root);
    end
end

% Pre-run grating order analysis (informational, no RCWA)
fprintf('\n--- Grating order analysis (pre-run) ---\n');
G_info = check_grating_orders(pitches(1), wavelength, n_substrate, ...
    n_background, angles(1));
if any(G_info.hoe_active)
    fprintf('[INFO] HOE active for %.0f%% of wavelength range. Energy log active.\n', ...
        mean(G_info.hoe_active) * 100);
end

pol_labels = {'TE', 'TM'};
pol_signs  = [ 1,   -1  ];

totalSteps = numel(pol_signs) * numel(angles) * numel(pitches) * ...
             numel(heights) * num_p1 * num_p2 * num_wavelengths;

if isempty(gcp('nocreate')), parpool; end
progressQueue = parallel.pool.DataQueue;
global progressCount %#ok<GVMIS>
progressCount = 0;
afterEach(progressQueue, @(~) updateProgress(totalSteps));

% Energy log accumulator
energy_log_entries = {};

%% =====================================================================
%% MAIN SIMULATION LOOP
%% =====================================================================
for pol_idx = 1:numel(pol_signs)
    pol_sign  = pol_signs(pol_idx);
    pol_label = pol_labels{pol_idx};
    fprintf('\n===== Polarization: %s =====\n', pol_label);

    for angle_idx = 1:numel(angles)
        theta = angles(angle_idx);

        for p_idx = 1:numel(pitches)
            pitch = pitches(p_idx);
            max_p1 = max_p1_fraction * pitch;
            p1_values = linspace(min_p1, max_p1, num_p1);
            p1_lim    = [min_p1, max_p1, num_p1];

            for h_idx = 1:numel(heights)
                h       = heights(h_idx);
                h_label = heights(h_idx);

                % --- CHECKPOINT: skip if already complete ---------------
                out_path = expected_matlib_path(base_path, spec, waveband, ...
                    pillar_mat_name, substrate_mat_name, timestamp, ...
                    pol_label, pitch, h_label, theta);
                if exist(out_path, 'file')
                    skipped = num_p1 * num_p2 * num_wavelengths;
                    progressCount = progressCount + skipped;
                    fprintf('  [SKIP] %s\n', out_path);
                    continue;
                end
                % --------------------------------------------------------

                trans_data     = zeros(num_wavelengths, num_p1, num_p2, 2);
                refl_data      = zeros(num_wavelengths, num_p1, num_p2, 2);
                trans_eff_data = zeros(num_wavelengths, num_p1, num_p2);
                refl_eff_data  = zeros(num_wavelengths, num_p1, num_p2);

                % Energy log arrays (allocated regardless; empty when unused)
                if enable_energy_log
                    T_total_data = zeros(num_wavelengths, num_p1, num_p2);
                    R_total_data = zeros(num_wavelengths, num_p1, num_p2);
                end

                for j1 = 1:num_p1
                    p1_val = p1_values(j1);

                    for j2 = 1:num_p2
                        p2_val = p2_values(j2);

                        % broadcast scalars for parfor
                        wl_arr = wavelength;
                        np_arr = n_pillar;
                        sp     = spec;
                        h_now  = h;
                        ns     = n_substrate;
                        nb     = n_background;
                        nc     = n_cap;
                        th     = theta;
                        pi_    = pitch;
                        hc     = h_cap;
                        ps     = pol_sign;
                        nn_    = nn;
                        do_log = enable_energy_log;

                        t_blk   = zeros(num_wavelengths, 2);
                        r_blk   = zeros(num_wavelengths, 2);
                        te_blk  = zeros(num_wavelengths, 1);
                        re_blk  = zeros(num_wavelengths, 1);
                        Tt_blk  = zeros(num_wavelengths, 1);
                        Rt_blk  = zeros(num_wavelengths, 1);

                        parfor k = 1:num_wavelengths
                            if do_log
                                [tr, rf, te, re, Tt, Rt] = RCWA_solve( ...
                                    sp, wl_arr(k), h_now, ns, np_arr(k), nb, nc, ...
                                    th, pi_, p1_val, p2_val, hc, ps, nn_); %#ok<PFBNS>
                                Tt_blk(k) = Tt;
                                Rt_blk(k) = Rt;
                            else
                                [tr, rf, te, re] = RCWA_solve( ...
                                    sp, wl_arr(k), h_now, ns, np_arr(k), nb, nc, ...
                                    th, pi_, p1_val, p2_val, hc, ps, nn_);
                            end

                            t_blk(k, :) = [abs(tr), angle(tr)];
                            r_blk(k, :) = [abs(rf), angle(rf)];
                            te_blk(k)   = te;
                            re_blk(k)   = re;

                            send(progressQueue, 1); %#ok<PFBNS>
                        end

                        trans_data(:, j1, j2, :)  = t_blk;
                        refl_data(:, j1, j2, :)   = r_blk;
                        trans_eff_data(:, j1, j2) = te_blk;
                        refl_eff_data(:, j1, j2)  = re_blk;

                        if enable_energy_log
                            T_total_data(:, j1, j2) = Tt_blk;
                            R_total_data(:, j1, j2) = Rt_blk;
                        end
                    end
                end

                % --- energy log for this block --------------------------
                if enable_energy_log
                    entry = compute_energy_log_entry( ...
                        wavelength, trans_eff_data, refl_eff_data, ...
                        T_total_data, R_total_data, ...
                        pol_label, theta, pitch, h_label, p1_values, p2_values, ...
                        HOE_warn_threshold, abs_warn_threshold, energy_bal_tol);
                    energy_log_entries{end+1} = entry; %#ok<AGROW>

                    % Print inline warning if thresholds exceeded
                    if entry.max_HOE_frac > HOE_warn_threshold
                        fprintf( ...
                            '  [HOE WARNING] %s theta%d P%.3f H%.2f: max HOE=%.3f at \x03BB=%.4f\xB5m\n', ...
                            pol_label, theta, pitch, h_label, ...
                            entry.max_HOE_frac, entry.max_HOE_wavelength);
                    end
                end

                % --- save -----------------------------------------------
                write_args = { ...
                    'Material', pillar_mat_name,    'pillar',     n_pillar, ...
                        'Experimental complex index', ...
                    'Material', substrate_mat_name, 'substrate',  n_substrate, 'Quartz', ...
                    'Material', 'air',              'background', n_background, 'Air', ...
                    'Material', 'cap',              'cap',        n_cap,        'Cap layer', ...
                    'Param',    'wavelength',        wavelength_lim, '', ...
                    'Param',    spec.param1_name,    p1_lim, spec.param1_label, ...
                };
                if spec.n_geom_params == 2
                    write_args = [write_args, { ...
                        'Param', spec.param2_name, p2_lim, spec.param2_label ...
                    }]; %#ok<AGROW>
                end
                write_args = [write_args, { ...
                    'Constant', 'height', h_label,    '', ...
                    'Constant', 'theta',  theta,       '', ...
                    'Constant', 'h_cap',  h_cap,       'cap layer thickness (um)', ...
                    'Constant', 'n_cap',  n_cap,       'cap layer refractive index', ...
                    'Constant', 'pitch',  pitch,       'unit cell pitch (um)', ...
                    'Constant', 'taper_mid_delta', ...
                        local_build_opt(spec, 'taper_mid_delta', NaN), ...
                        'middle major width offset from top width (um)', ...
                    'Constant', 'taper_bottom_delta', ...
                        local_build_opt(spec, 'taper_bottom_delta', NaN), ...
                        'bottom major width offset from top width (um)', ...
                    'Constant', 'taper_num_slices', ...
                        local_build_opt(spec, 'taper_num_slices', NaN), ...
                        'number of vertical taper slices', ...
                    'Data', 'transmission_bottom_0_0', trans_data, ...
                        '[abs(t)  angle(t)] — 0-order transmitted amplitude', ...
                    'Data', 'reflection_bottom_0_0', refl_data, ...
                        '[abs(r)  angle(r)] — 0-order reflected amplitude', ...
                    'Data', 'transmission_bottom_0_0_efficiency', trans_eff_data, ...
                        '0-order transmitted power efficiency (0-1)', ...
                    'Data', 'reflection_bottom_0_0_efficiency', refl_eff_data, ...
                        '0-order reflected power efficiency (0-1)', ...
                    'Creator', 'Rahul Shah', ...
                    'Notes', sprintf('Shape: %s | Pol: %s | Timestamp: %s', ...
                        spec.shape_name, pol_label, timestamp) ...
                }]; %#ok<AGROW>

                WriteMatLib(spec, waveband, 'um', 'AmpPhase', ...
                    pitch, h_label, pol_label, timestamp, base_path, ...
                    write_args{:});

            end  % heights
        end  % pitches
    end  % angles
end  % polarizations

%% =====================================================================
%% ENERGY LOG FILE
%% =====================================================================
if enable_energy_log && ~isempty(energy_log_entries)
    write_energy_log(energy_log_entries, base_path, spec, ...
        pillar_mat_name, substrate_mat_name, timestamp, ...
        HOE_warn_threshold, abs_warn_threshold);
end

%% =====================================================================
%% POST-PROCESSING
%% =====================================================================
te_dir  = fullfile(run_root, 'TE');
tm_dir  = fullfile(run_root, 'TM');
avg_dir = fullfile(run_root, 'Averaged');

fprintf('\n===== Building per-polarization filter tables =====\n');
build_filter_table(te_dir, spec, make_plots);
build_filter_table(tm_dir, spec, make_plots);

fprintf('\n===== Averaging TE + TM =====\n');
average_te_tm(te_dir, tm_dir, avg_dir, wavelength);

fprintf('\n===== PIPELINE COMPLETE =====\n');
fprintf('Timestamp : %s\n', timestamp);
fprintf('Shape     : %s\n', spec.display_name);
fprintf('Results   : %s\n', run_root);
fprintf('Final CSVs: %s\n', avg_dir);
if enable_energy_log
    fprintf('Energy log: %s\n', fullfile(run_root, ...
        sprintf('energy_log_%s.txt', timestamp)));
end

%% =====================================================================
%% LOCAL FUNCTIONS
%% =====================================================================

function entry = compute_energy_log_entry(wavelength, T0, R0, Tt, Rt, ...
        pol, theta, pitch, height, p1_values, p2_values, ...
        HOE_thresh, abs_thresh, bal_tol)
% Compute per-block energy balance statistics and flag threshold breaches.

    % Average over all geometry combinations for the block-level summary
    T0_mean  = mean(T0,  [2 3]);   % [Nw x 1]
    R0_mean  = mean(R0,  [2 3]);
    Tt_mean  = mean(Tt, [2 3]);
    Rt_mean  = mean(Rt, [2 3]);

    HOE_per_wl  = (Tt_mean - T0_mean(:)) + (Rt_mean - R0_mean(:));
    abs_per_wl  = 1 - (Tt_mean + Rt_mean);
    bal_per_wl  = Tt_mean + Rt_mean;   % expected ≈ 1 for lossless, < 1 with absorption

    [max_HOE, max_HOE_idx] = max(HOE_per_wl);
    [max_abs, ~]           = max(abs_per_wl);
    min_bal                = min(bal_per_wl);

    entry.pol              = pol;
    entry.theta            = theta;
    entry.pitch            = pitch;
    entry.height           = height;
    entry.wavelength       = wavelength;
    entry.HOE_per_wl       = HOE_per_wl(:).';
    entry.abs_per_wl       = abs_per_wl(:).';
    entry.bal_per_wl       = bal_per_wl(:).';
    entry.max_HOE_frac     = max_HOE;
    entry.max_HOE_wavelength = wavelength(max_HOE_idx);
    entry.max_abs_frac     = max_abs;
    entry.min_energy_bal   = min_bal;
    entry.HOE_flagged      = max_HOE > HOE_thresh;
    entry.abs_flagged      = max_abs > abs_thresh;
    entry.bal_flagged      = abs(min_bal - 1) > bal_tol && min_bal > 1 + bal_tol;
    % Note: min_bal < 1 is normal (absorption). Only flag if > 1 (numerical error).

    entry.n_p1   = numel(p1_values);
    entry.n_p2   = numel(p2_values);
end

% -----------------------------------------------------------------------
function write_energy_log(entries, base_path, spec, pillar_mat, ...
        substrate_mat, timestamp, HOE_thresh, abs_thresh)
% Write human-readable energy balance report to a text file.

    material_folder = sprintf('%s_on_%s_%s', ...
        pillar_mat, substrate_mat, spec.shape_name);
    run_root  = fullfile(base_path, material_folder, timestamp);
    log_file  = fullfile(run_root, sprintf('energy_log_%s.txt', timestamp));

    if ~exist(run_root, 'dir'), mkdir(run_root); end

    fid = fopen(log_file, 'w');
    if fid == -1
        warning('RunLibraryPipeline:logWriteFailed', ...
            'Could not write energy log to: %s', log_file);
        return;
    end

    fprintf(fid, 'ENERGY CONSERVATION LOG\n');
    fprintf(fid, '======================\n');
    fprintf(fid, 'Shape     : %s\n', spec.display_name);
    fprintf(fid, 'Timestamp : %s\n', timestamp);
    fprintf(fid, 'HOE threshold : %.3f (%.1f%%)\n', HOE_thresh, HOE_thresh*100);
    fprintf(fid, 'Abs threshold : %.3f (%.1f%%)\n', abs_thresh, abs_thresh*100);
    fprintf(fid, '\nINTERPRETATION GUIDE\n');
    fprintf(fid, '  HOE fraction = (T_all - T0) + (R_all - R0)\n');
    fprintf(fid, '    Energy diffracted into non-zero orders.\n');
    fprintf(fid, '    HOE > 0 means structure is NOT subwavelength in at least one medium.\n');
    fprintf(fid, '  Absorption fraction = 1 - (T_all + R_all)\n');
    fprintf(fid, '    Energy absorbed by the pillar material when k > 0.\n');
    fprintf(fid, '    This is PHYSICAL, not a numerical artifact.\n');
    fprintf(fid, '  Energy balance = T_all + R_all\n');
    fprintf(fid, '    < 1.0  : absorption present (normal for Si)\n');
    fprintf(fid, '    > 1.0  : numerical error — increase nn\n');
    fprintf(fid, '\n%s\n', repmat('=', 1, 90));

    n_HOE_flagged = 0;
    for ei = 1:numel(entries)
        e = entries{ei};
        flag_str = '';
        if e.HOE_flagged, flag_str = [flag_str '  *** HOE > threshold ***']; end
        if e.abs_flagged, flag_str = [flag_str '  [high absorption]']; end
        if e.bal_flagged, flag_str = [flag_str '  [*** energy > 1: check nn ***]']; end
        if e.HOE_flagged, n_HOE_flagged = n_HOE_flagged + 1; end

        fprintf(fid, '\n%s | theta=%2d | Pitch=%.3f | H=%.2f%s\n', ...
            e.pol, e.theta, e.pitch, e.height, flag_str);
        fprintf(fid, '  Max HOE fraction : %.4f  at lambda=%.4f um\n', ...
            e.max_HOE_frac, e.max_HOE_wavelength);
        fprintf(fid, '  Max absorption   : %.4f\n', e.max_abs_frac);
        fprintf(fid, '  Min energy bal   : %.4f  (1-min = %.4f absorbed)\n', ...
            e.min_energy_bal, 1 - e.min_energy_bal);
    end

    fprintf(fid, '\n%s\n', repmat('=', 1, 90));
    fprintf(fid, 'SUMMARY: %d / %d blocks exceeded HOE threshold (%.1f%%)\n', ...
        n_HOE_flagged, numel(entries), HOE_thresh * 100);
    fclose(fid);
    fprintf('Energy log written to:\n  %s\n', log_file);
end

% -----------------------------------------------------------------------
function fp = expected_matlib_path(base_path, spec, wavelength_band, ...
        pillar_mat, substrate_mat, timestamp, pol, pitch, height, theta)
    material_folder = sprintf('%s_on_%s_%s', pillar_mat, substrate_mat, spec.shape_name);
    pitch_folder    = sprintf('Pitch_%05.3f', pitch);
    height_folder   = sprintf('Height_%04.2f', height);
    height_int      = round(height * 100);
    pitch_int       = round(pitch  * 100);
    base_fn         = sprintf('%s_%s_on_%s_%s_H%04d_P%04d', ...
        wavelength_band, pillar_mat, substrate_mat, spec.shape_name, ...
        height_int, pitch_int);
    filename        = sprintf('%s_theta%d.mat', base_fn, round(theta));
    save_dir        = fullfile(base_path, material_folder, timestamp, ...
        pol, height_folder, pitch_folder);
    fp              = fullfile(save_dir, filename);
end

function val = local_build_opt(spec, name, default_val)
    val = default_val;
    if isfield(spec, 'build_options') && isfield(spec.build_options, name)
        val = spec.build_options.(name);
    end
end

% -----------------------------------------------------------------------
function updateProgress(totalSteps)
    global progressCount %#ok<GVMIS>
    progressCount = progressCount + 1;
    fprintf('Progress: %5.2f%%  (%d / %d)\n', ...
        (progressCount / totalSteps) * 100, progressCount, totalSteps);
end
