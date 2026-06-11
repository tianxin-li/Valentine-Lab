function csv_paths = build_filter_table(main_directory, spec, make_plots)
% BUILD_FILTER_TABLE  Build per-theta transmittance CSVs from library .mat files.
%
%   csv_paths = build_filter_table(main_directory, spec, make_plots)
%
%   Unified replacement for build_filter_table_cross and equivalents.
%   Works for any shape registered in shape_registry. Shape-specific logic
%   (row naming, param labels) comes entirely from the 'spec' argument.
%
%   INPUTS
%     main_directory : folder directly containing Height_*/Pitch_* subfolders
%                      (either the TE or TM polarization folder)
%     spec           : shape spec struct from shape_registry(shape_name)
%     make_plots     : logical, save PNG/FIG overview plots (default true)
%
%   RETURNS
%     csv_paths : cell array of CSV paths written (one per theta value)
%
%   CSV FORMAT
%     Each row is one filter (one combination of height, pitch, p1, p2).
%     Columns: FilterName | Wavelength_1 | Wavelength_2 | ... | Wavelength_N
%     Values are 0-order transmitted power efficiency (0-1).
%
%   CSV FILENAME
%     <main_directory>/TransmissionTable_<shape_tag>_<theta_key>.csv

    if nargin < 3 || isempty(make_plots)
        make_plots = true;
    end

    if ~isfolder(main_directory)
        error('build_filter_table:badDir', ...
            'Not a valid directory: %s', main_directory);
    end

    height_folders = dir(fullfile(main_directory, 'Height_*'));
    if isempty(height_folders)
        error('build_filter_table:noHeightFolders', ...
            'No Height_* subfolders found in: %s', main_directory);
    end

    % theta_key -> struct('wavelength', [1xNw], 'trans', [MxNw], 'names', {1xM})
    theta_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
    theta_pat = 'theta(-?\d+)\.mat$';
    total_files_read = 0;

    %% --- walk Height_* / Pitch_* and ingest every theta*.mat -----------
    for h_idx = 1:numel(height_folders)
        if ~height_folders(h_idx).isdir, continue; end

        h_folder_path = fullfile(main_directory, height_folders(h_idx).name);
        h_val = str2double(strrep(height_folders(h_idx).name, 'Height_', ''));

        pitch_folders = dir(fullfile(h_folder_path, 'Pitch_*'));

        for p_idx = 1:numel(pitch_folders)
            if ~pitch_folders(p_idx).isdir, continue; end

            p_folder_path = fullfile(h_folder_path, pitch_folders(p_idx).name);
            p_val = str2double(strrep(pitch_folders(p_idx).name, 'Pitch_', ''));

            theta_files = dir(fullfile(p_folder_path, '*theta*.mat'));
            if isempty(theta_files)
                warning('build_filter_table:noFiles', ...
                    'No theta*.mat files in: %s', p_folder_path);
                continue;
            end

            for tf_idx = 1:numel(theta_files)
                this_name = theta_files(tf_idx).name;
                tok = regexp(this_name, theta_pat, 'tokens', 'once');
                if isempty(tok), continue; end
                theta_key = ['theta' tok{1}];

                filepath = fullfile(p_folder_path, this_name);

                % Read via unified reader
                info = read_matfile(filepath);
                if ~info.ok
                    warning('build_filter_table:badFile', ...
                        'Skipping %s: %s', filepath, info.msg);
                    continue;
                end

                % Sanity-check: shape in file matches the spec we were given
                if ~isempty(info.shape_name) && ...
                   ~strcmpi(info.shape_name, 'unknown') && ...
                   ~strcmpi(info.shape_name, spec.shape_name)
                    warning('build_filter_table:shapeMismatch', ...
                        'File shape "%s" does not match spec shape "%s". Skipping %s.', ...
                        info.shape_name, spec.shape_name, filepath);
                    continue;
                end

                % --- build rows from this file --------------------------
                % trans_eff shape: [Nw x Np1 x Np2]  (Np2 = 1 for 1-param shapes)
                te = info.trans_eff;
                Nw  = numel(info.wavelength);
                Np1 = numel(info.p1_values);

                if info.n_geom_params == 2
                    Np2 = numel(info.p2_values);
                else
                    Np2 = 1;
                end

                rows_here  = Np1 * Np2;
                row_block  = zeros(rows_here, Nw);
                name_block = cell(1, rows_here);

                r = 0;
                for j1 = 1:Np1
                    p1_val = info.p1_values(j1);

                    for j2 = 1:Np2
                        r = r + 1;

                        if info.n_geom_params == 2
                            p2_val = info.p2_values(j2);
                        else
                            p2_val = 1;   % dummy, ignored by row_name_fn
                        end

                        % Extract the spectrum for this (j1, j2) combination.
                        % te is [Nw x Np1 x Np2]; squeeze to a column vector.
                        spectrum = squeeze(te(:, j1, j2));
                        if size(spectrum, 1) == 1
                            spectrum = spectrum.';   % force column
                        end
                        row_block(r, :) = spectrum.';

                        % Row name via spec's registered function
                        name_block{r} = spec.row_name_fn( ...
                            h_val, p_val, p1_val, p2_val);
                    end
                end

                % --- accumulate into theta_map -------------------------
                if isKey(theta_map, theta_key)
                    S = theta_map(theta_key);
                    if numel(S.wavelength) ~= Nw || ...
                       any(abs(S.wavelength - info.wavelength(:).') > 1e-9)
                        warning('build_filter_table:wlMismatch', ...
                            'Wavelength grid mismatch for %s in %s. Skipping.', ...
                            theta_key, filepath);
                    else
                        S.trans = [S.trans; row_block];    %#ok<AGROW>
                        S.names = [S.names, name_block];   %#ok<AGROW>
                        theta_map(theta_key) = S;
                    end
                else
                    theta_map(theta_key) = struct( ...
                        'wavelength', info.wavelength(:).', ...
                        'trans',      row_block, ...
                        'names',      {name_block});
                end

                total_files_read = total_files_read + 1;
            end
        end
    end

    if total_files_read == 0
        error('build_filter_table:noFilesRead', ...
            'No valid theta*.mat files found under: %s', main_directory);
    end

    %% --- emit one CSV (and optional plot) per theta -------------------
    theta_keys = theta_map.keys;
    fprintf('Theta sets found: %s\n', strjoin(theta_keys, ', '));
    csv_paths = {};

    for k = 1:numel(theta_keys)
        key = theta_keys{k};
        S   = theta_map(key);

        if isempty(S.trans)
            warning('build_filter_table:noRows', ...
                'No rows for %s. Skipping.', key);
            continue;
        end

        Nw = numel(S.wavelength);

        % Column headers: Wavelength_1 ... Wavelength_N
        var_names = arrayfun(@(j) sprintf('Wavelength_%d', j), ...
            1:Nw, 'UniformOutput', false);

        T = array2table(S.trans, 'VariableNames', var_names);
        T = addvars(T, S.names.', 'Before', 1, 'NewVariableNames', 'FilterName');

        csv_name = fullfile(main_directory, ...
            sprintf('TransmissionTable_%s_%s.csv', spec.shape_tag, key));
        writetable(T, csv_name);
        csv_paths{end+1} = csv_name; %#ok<AGROW>
        fprintf('  Saved %s  (%d filters, %d wavelengths)\n', ...
            csv_name, size(S.trans, 1), Nw);

        if make_plots
            f = figure('Position', [100 100 1200 800], 'Visible', 'off');
            hold on;
            for ii = 1:size(S.trans, 1)
                plot(S.wavelength, S.trans(ii, :), 'LineWidth', 0.8);
            end
            xlabel('Wavelength (\mum)', 'FontSize', 12);
            ylabel('Transmission efficiency', 'FontSize', 12);
            title(sprintf('%s Transmission Spectra — %s', spec.display_name, key), ...
                'FontSize', 13);
            grid on; ylim([0 1]); box on; hold off;

            png_name = fullfile(main_directory, ...
                sprintf('AllSpectra_%s_%s.png', spec.shape_tag, key));
            fig_name = fullfile(main_directory, ...
                sprintf('AllSpectra_%s_%s.fig', spec.shape_tag, key));
            try
                saveas(f, png_name);
                saveas(f, fig_name);
            catch ME
                warning('build_filter_table:plotFail', ...
                    'Could not save plots for %s: %s', key, ME.message);
            end
            close(f);
        end
    end

    fprintf('build_filter_table done: %s\n', main_directory);
end
