%% PATCH NOTES — three targeted changes across existing files
%
%  Apply these changes manually (described precisely below) or copy the
%  replacement code blocks directly into each file.
%
%  Changes:
%    1. read_matfile.m          — unpack stored pitch from .mat constants
%    2. RunLibraryPipeline.m    — store pitch as constant + checkpoint skip
%    3. MetasurfaceExplorer.m   — use info.pitch instead of folder regex
%
% =========================================================================
% 1. read_matfile.m
%    FIND (around line 95, after the n_cap line in the constants section):
%
%        info.h_cap  = local_const_scalar(raw, 'h_cap');
%        info.n_cap  = local_const_scalar(raw, 'n_cap');
%
%    REPLACE WITH:
%
%        info.h_cap  = local_const_scalar(raw, 'h_cap');
%        info.n_cap  = local_const_scalar(raw, 'n_cap');
%        info.pitch  = local_const_scalar(raw, 'pitch');   % <-- ADD THIS LINE
%
%  That's the entire change to read_matfile.m.
%
% =========================================================================
% 2. RunLibraryPipeline.m — TWO sub-changes:
%
% --- 2a. Store pitch in write_args ----------------------------------------
%    FIND (in the write_args block, after the h_cap/n_cap constants):
%
%        'Constant', 'h_cap',  h_cap,       'cap layer thickness (um)', ...
%        'Constant', 'n_cap',  n_cap,       'cap layer refractive index', ...
%
%    REPLACE WITH:
%
%        'Constant', 'h_cap',  h_cap,       'cap layer thickness (um)', ...
%        'Constant', 'n_cap',  n_cap,       'cap layer refractive index', ...
%        'Constant', 'pitch',  pitch,       'unit cell pitch (um)', ...    % <-- ADD
%
% --- 2b. Add checkpoint skip at the top of the height loop ---------------
%    FIND (at the start of the   for h_idx = 1:numel(heights)   body,
%          just after the two lines:  h = heights(h_idx);  h_label = ...):
%
%        h       = heights(h_idx);
%        h_label = heights(h_idx);
%
%        % Pre-allocate data arrays...
%        trans_data = zeros(...);
%
%    INSERT the following block BETWEEN those two groups:
%
%        % --- CHECKPOINT: skip if output already exists -------------------
%        out_path = expected_matlib_path(base_path, spec, waveband, ...
%            pillar_mat_name, substrate_mat_name, timestamp, pol_label, ...
%            pitch, h_label, theta);
%        if exist(out_path, 'file')
%            skipped = num_p1 * num_p2 * num_wavelengths;
%            progressCount = progressCount + skipped;
%            fprintf('  [SKIP] %s\n', out_path);
%            fprintf('Progress: %5.2f%%  (skipped %d steps)\n', ...
%                (progressCount / totalSteps) * 100, skipped);
%            continue;
%        end
%        % -----------------------------------------------------------------
%
% --- 2c. Add helper function at the bottom of RunLibraryPipeline.m -------
%    At the very end of RunLibraryPipeline.m, BEFORE the closing line of
%    the updateProgress function, ADD this new nested function:
%
%        function fp = expected_matlib_path(base_path, spec, ...
%                wavelength_band, pillar_mat, substrate_mat, ...
%                timestamp, pol, pitch, height, theta)
%        % Returns the full path WriteMatLib would produce for these inputs.
%        % Must stay in sync with WriteMatLib path construction logic.
%            material_folder = sprintf('%s_on_%s_%s', ...
%                pillar_mat, substrate_mat, spec.shape_name);
%            pitch_folder    = sprintf('Pitch_%05.3f', pitch);
%            height_folder   = sprintf('Height_%04.2f', height);
%            height_int      = round(height * 100);
%            pitch_int       = round(pitch  * 100);
%            base_fn         = sprintf('%s_%s_on_%s_%s_H%04d_P%04d', ...
%                wavelength_band, pillar_mat, substrate_mat, ...
%                spec.shape_name, height_int, pitch_int);
%            filename        = sprintf('%s_theta%d.mat', base_fn, round(theta));
%            save_dir        = fullfile(base_path, material_folder, ...
%                timestamp, pol, height_folder, pitch_folder);
%            fp              = fullfile(save_dir, filename);
%        end
%
% =========================================================================
% 3. MetasurfaceExplorer.m — update viewerComputeField pitch resolution
%    FIND (in the viewerComputeField nested function, the pitch block):
%
%        sel_idx = find(strcmp(viewerFileList.Items, viewerFileList.Value), 1);
%        pitch = parsePitchFromPath(viewerFiles(sel_idx).folder);
%        if isnan(pitch)
%            setStatus(viewerStatusLabel, 'Cannot determine pitch from folder name.'); return;
%        end
%
%    REPLACE WITH:
%
%        % Prefer pitch stored in the .mat; fall back to folder-name parsing
%        % for files generated before the pitch-constant update.
%        pitch = viewerInfo.pitch;
%        if isnan(pitch)
%            sel_idx = find(strcmp(viewerFileList.Items, viewerFileList.Value), 1);
%            pitch = parsePitchFromPath(viewerFiles(sel_idx).folder);
%        end
%        if isnan(pitch)
%            setStatus(viewerStatusLabel, 'Cannot determine pitch (not in file or folder name).'); return;
%        end
%
% =========================================================================
% END OF PATCH NOTES
