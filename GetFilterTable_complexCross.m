clc; clearvars; close all;

%% Pick the root folder that contains Height_*/Pitch_* subfolders
main_directory = uigetdir(fullfile(pwd, 'Library Data/'), ...
    'Select the main directory containing the Height/Pitch folders');
if ~isfolder(main_directory)
    error('The selected directory is not valid.');
end

% Find all Height_* folders
height_folders = dir(fullfile(main_directory, 'Height_*'));

% Map of theta_key -> struct('wavelength', [1xN], 'trans', [M x N], 'names', {1xM cell})
theta_map = containers.Map('KeyType','char','ValueType','any');

% Regex to extract numeric angle from filenames (e.g., theta0.mat, theta20.mat, theta-10.mat)
theta_pat = 'theta(-?\d+)\.mat$';

total_theta_files = 0;

%% Walk the tree and ingest every theta*.mat (Complex cross: width × aspect; uses data_values{3})
for h_idx = 1:numel(height_folders)
    if ~height_folders(h_idx).isdir, continue; end
    height_folder_path = fullfile(main_directory, height_folders(h_idx).name);

    pitch_folders = dir(fullfile(height_folder_path, 'Pitch_*'));
    for p_idx = 1:numel(pitch_folders)
        if ~pitch_folders(p_idx).isdir, continue; end
        pitch_folder_path = fullfile(height_folder_path, pitch_folders(p_idx).name);

        % Find *theta*.mat files in this Pitch folder
        theta_files = dir(fullfile(pitch_folder_path, '*theta*.mat'));
        if isempty(theta_files)
            warning('No theta*.mat files found in: %s', pitch_folder_path);
            continue;
        end

        for tf_idx = 1:numel(theta_files)
            this_name = theta_files(tf_idx).name;
            tok = regexp(this_name, theta_pat, 'tokens', 'once');
            if isempty(tok)
                % Not a canonical theta file name — skip
                continue;
            end
            theta_val_str = tok{1};               % e.g., '0', '20', '-10'
            theta_key = ['theta' theta_val_str];  % e.g., 'theta20'

            filePath = fullfile(pitch_folder_path, this_name);
            try
                filedata = load(filePath);
            catch ME
                warning('Failed to load %s: %s', filePath, ME.message);
                continue;
            end

            % Expect:
            % param_values{1,1} = [min_wavelength, max_wavelength, no_of_wavelength]
            % param_values{1,2} = [min_width,      max_width,      no_of_width]
            % param_values{1,3} = [min_aspect,     max_aspect,     no_of_aspect]
            % data_values{3}    = transmission for complex crosses
            if ~isfield(filedata, 'param_values') || ~iscell(filedata.param_values) || ...
               ~isfield(filedata, 'data_values')  || ~iscell(filedata.data_values)
                warning('Unexpected data structure in %s. Skipping.', filePath);
                continue;
            end

            try
                min_wavelength   = filedata.param_values{1,1}(1);
                max_wavelength   = filedata.param_values{1,1}(2);
                no_of_wavelength = filedata.param_values{1,1}(3);

                min_width   = filedata.param_values{1,2}(1);
                max_width   = filedata.param_values{1,2}(2);
                no_of_width = filedata.param_values{1,2}(3);

                min_aspect   = filedata.param_values{1,3}(1);
                max_aspect   = filedata.param_values{1,3}(2);
                no_of_aspect = filedata.param_values{1,3}(3);

                wavelength_values = linspace(min_wavelength, max_wavelength, no_of_wavelength);
                width_values      = linspace(min_width,      max_width,      no_of_width);
                aspect_values     = linspace(min_aspect,     max_aspect,     no_of_aspect);

                % Use complex-cross transmission “as-is”. If these are fields, switch to abs(.)^2
                trans_data = filedata.data_values{3};
                % Expected shape: [no_of_wavelength x no_of_width x no_of_aspect x ...]
            catch
                warning('Malformed param/data fields in %s. Skipping.', filePath);
                continue;
            end

            % Build rows (one per [width, aspect]) and names for this file
            rows_here  = no_of_width * no_of_aspect;
            row_block  = zeros(rows_here, numel(wavelength_values));
            name_block = cell(1, rows_here);

            r = 0;
            for w_idx = 1:no_of_width
                for a_idx = 1:no_of_aspect
                    r = r + 1;
                    row_block(r, :) = (squeeze(trans_data(:, w_idx, a_idx))).';
                    circle_diameter = width_values(w_idx) * aspect_values(a_idx); % derived
                    name_block{r} = sprintf('%s_%s_Width_%.3f_AspectRatio_%.2f_circle_diameter_%.3f_ComplexCross', ...
                        height_folders(h_idx).name, pitch_folders(p_idx).name, ...
                        width_values(w_idx), aspect_values(a_idx), circle_diameter);
                end
            end

            % Append into theta_map (enforce wavelength consistency per theta)
            if isKey(theta_map, theta_key)
                S = theta_map(theta_key);
                if numel(S.wavelength) ~= numel(wavelength_values) || ...
                   any(abs(S.wavelength - wavelength_values) > 1e-12)
                    warning(['Wavelength grid mismatch for %s in %s. ' ...
                             'Skipping these rows to keep CSV consistent.'], ...
                             theta_key, filePath);
                else
                    S.trans = [S.trans; row_block];        %#ok<AGROW>
                    S.names = [S.names, name_block];       %#ok<AGROW>
                    theta_map(theta_key) = S;
                end
            else
                theta_map(theta_key) = struct( ...
                    'wavelength', wavelength_values(:).', ...
                    'trans', row_block, ...
                    'names', {name_block});
            end

            total_theta_files = total_theta_files + 1;
        end
    end
end

if total_theta_files == 0
    error('No theta*.mat files were discovered under %s', main_directory);
end

%% Emit one CSV (and a plot) per theta
theta_keys = theta_map.keys;
fprintf('Discovered theta sets: %s\n', strjoin(theta_keys, ', '));

for k = 1:numel(theta_keys)
    key = theta_keys{k};
    S = theta_map(key);

    if isempty(S.trans)
        warning('No rows accumulated for %s. Skipping export.', key);
        continue;
    end

    % Create table: [FilterName | Wavelength_1 ... Wavelength_N]
    Nw = numel(S.wavelength);
    varNames = strings(1, Nw);
    for jj = 1:Nw
        varNames(jj) = "Wavelength_" + string(jj);
    end
    transmission_table = array2table(S.trans, 'VariableNames', cellstr(varNames));
    transmission_table = addvars(transmission_table, S.names.', ...
        'Before', 1, 'NewVariableNames', 'FilterName');

    % Save CSV
    csv_name = fullfile(main_directory, sprintf('TransmissionTable_ComplexCross_%s.csv', key));
    writetable(transmission_table, csv_name);
    fprintf('Saved %s with %d rows and %d wavelengths.\n', csv_name, size(S.trans,1), size(S.trans,2));

    % Plot and save (hidden figure for speed)
    f = figure('Position', [100 100 1200 800], 'Visible', 'off');
    hold on;
    for ii = 1:size(S.trans, 1)
        plot(S.wavelength, S.trans(ii, :), 'LineWidth', 1);
    end
    xlabel('Wavelength (\mum)', 'FontSize', 12);
    ylabel('Transmission', 'FontSize', 12);
    title(sprintf('All Complex Cross Transmission Spectra — %s', key), 'FontSize', 14);
    grid on; ylim([0 1]); box on; hold off;

    png_name = fullfile(main_directory, sprintf('AllTransmissionSpectra_ComplexCross_%s.png', key));
    fig_name = fullfile(main_directory, sprintf('AllTransmissionSpectra_ComplexCross_%s.fig', key));
    try
        saveas(f, png_name);
        saveas(f, fig_name);
        fprintf('Saved plots: %s and %s\n', png_name, fig_name);
    catch ME
        warning('Failed to save plots for %s: %s', key, ME.message);
    end
    close(f);
end

fprintf('Done. One CSV (and plot) per theta value has been created in:\n%s\n', main_directory);
