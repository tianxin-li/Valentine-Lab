clc; clearvars; close all;

%% 1. Setup & User Configuration
% Pick the root folder that contains Height_*/Pitch_* subfolders
main_directory = uigetdir(fullfile(pwd, 'Library Data/Si_on_SiO2_circle_with_cap'), ...
    'Select the main directory containing the Height/Pitch folders');

if ~isfolder(main_directory)
    error('The selected directory is not valid.');
end

% --- Ask user for target number of data points ---
prompt = {'Enter desired number of wavelength points (Leave empty to keep original):'};
dlgtitle = 'Interpolation Settings';
dims = [1 50];
definput = {''};
answer = inputdlg(prompt, dlgtitle, dims, definput);

target_points = [];
if ~isempty(answer) && ~isempty(answer{1})
    target_points = str2double(answer{1});
    if isnan(target_points) || target_points <= 1
        warning('Invalid number entered. Reverting to original data resolution.');
        target_points = [];
    else
        fprintf('Interpolation active: Resampling all data to %d points.\n', target_points);
    end
end

% Find all Height_* folders
height_folders = dir(fullfile(main_directory, 'Height_*'));
theta_map = containers.Map('KeyType','char','ValueType','any');
theta_pat = 'theta(-?\d+)\.mat$';

%% 2. Walk the tree and ingest every theta*.mat
total_theta_files = 0;

for h_idx = 1:numel(height_folders)
    height_folder_path = fullfile(main_directory, height_folders(h_idx).name);
    if ~height_folders(h_idx).isdir, continue; end
    
    pitch_folders = dir(fullfile(height_folder_path, 'Pitch_*'));
    
    for p_idx = 1:numel(pitch_folders)
        pitch_folder_path = fullfile(height_folder_path, pitch_folders(p_idx).name);
        if ~pitch_folders(p_idx).isdir, continue; end
        
        theta_files = dir(fullfile(pitch_folder_path, '*theta*.mat'));
        if isempty(theta_files), continue; end
        
        for tf_idx = 1:numel(theta_files)
            this_name = theta_files(tf_idx).name;
            tok = regexp(this_name, theta_pat, 'tokens', 'once');
            if isempty(tok), continue; end
            
            theta_val_str = tok{1};
            theta_key = ['theta' theta_val_str];
            filePath = fullfile(pitch_folder_path, this_name);
            
            try
                filedata = load(filePath);
            catch ME
                warning('Failed to load %s: %s', filePath, ME.message);
                continue;
            end
            
            if ~isfield(filedata, 'param_values') || ~isfield(filedata.data_values, 'data_values') % Check structure
                 % Note: Sometimes data_values is the field name itself depending on save format.
                 % Assuming your previous code structure was correct:
            end
            
            try
                min_wavelength   = filedata.param_values{1,1}(1);
                max_wavelength   = filedata.param_values{1,1}(2);
                no_of_wavelength = filedata.param_values{1,1}(3);
                
                min_diameter   = filedata.param_values{1,2}(1);
                max_diameter   = filedata.param_values{1,2}(2);
                no_of_diameter = filedata.param_values{1,2}(3);
                
                orig_wavelength_values = linspace(min_wavelength, max_wavelength, no_of_wavelength);
                
                % Load Data
                raw_trans_data = filedata.data_values{1} .* filedata.data_values{1};
                data_slice = squeeze(raw_trans_data(:, :, 1)); 

                % --- SAFETY CHECK: Fix Data Orientation ---
                % We need data_slice to be [Wavelengths x Diameter]
                % If it's a vector, force it to be a COLUMN vector (Nx1)
                if isvector(data_slice)
                    data_slice = data_slice(:);
                end
                
                % If dimensions are transposed (Diameter x Wavelength), flip it
                if size(data_slice, 1) ~= no_of_wavelength && size(data_slice, 2) == no_of_wavelength
                    data_slice = data_slice.'; 
                end
                % ------------------------------------------
                
                diameter_values = linspace(min_diameter, max_diameter, no_of_diameter);
                
                % --- Interpolation Logic ---
                if ~isempty(target_points)
                    final_wavelength_values = linspace(min_wavelength, max_wavelength, target_points);
                    % interp1 operates on COLUMNS. Since we forced data_slice to have
                    % wavelengths as rows, this produces [Target_Points x Diameter]
                    processed_slice = interp1(orig_wavelength_values, data_slice, final_wavelength_values, 'pchip');
                else
                    final_wavelength_values = orig_wavelength_values;
                    processed_slice = data_slice;
                end
                
            catch
                warning('Malformed param/data fields in %s. Skipping.', filePath);
                continue;
            end
            
            % Transpose so Rows = Filters, Cols = Wavelengths
            row_block = processed_slice.'; 
            
            name_block = cell(1, no_of_diameter);
            for d_idx = 1:no_of_diameter
                name_block{d_idx} = sprintf('%s_%s_Diameter_%.3f_Si_Pillars', ...
                    height_folders(h_idx).name, pitch_folders(p_idx).name, diameter_values(d_idx));
            end
            
            add_to_theta_map(theta_map, theta_key, final_wavelength_values, row_block, name_block);
            total_theta_files = total_theta_files + 1;
        end
    end
end

if total_theta_files == 0
    error('No theta*.mat files were discovered under %s', main_directory);
end

%% 3. Emit CSV and Plots
theta_keys = theta_map.keys;
fprintf('Discovered theta sets: %s\n', strjoin(theta_keys, ', '));

for k = 1:numel(theta_keys)
    key = theta_keys{k};
    S = theta_map(key);
    
    if isempty(S.trans)
        warning('No rows accumulated for %s. Skipping export.', key);
        continue;
    end
    
    Nw = numel(S.wavelength);
    varNames = strings(1, Nw);
    for jj = 1:Nw
        varNames(jj) = "Wavelength_" + string(jj);
    end
    
    % DEBUG CHECK: Ensure dimensions match before table creation
    if size(S.trans, 2) ~= Nw
        warning('Dimension mismatch for %s. Trans Rows: %d, Trans Cols: %d, Wavelengths: %d', ...
            key, size(S.trans, 1), size(S.trans, 2), Nw);
        % Attempt fallback transpose if likely inverted
        if size(S.trans, 1) == Nw
            S.trans = S.trans.';
            fprintf('Auto-corrected transposition for %s.\n', key);
        end
    end

    try
        transmission_table = array2table(S.trans, 'VariableNames', cellstr(varNames));
        transmission_table = addvars(transmission_table, S.names.', ...
            'Before', 1, 'NewVariableNames', 'FilterName');
        
        angle_num = erase(key, 'theta');          
        if startsWith(angle_num, '-')
            angle_suffix = ['theta' angle_num]; 
        else
            angle_suffix = ['theta' angle_num];
        end
        
        if ~isempty(target_points)
            res_tag = sprintf('_%dpts', target_points);
        else
            res_tag = '';
        end
        
        csv_name = fullfile(main_directory, sprintf('TransmissionTable_NIR_circle_%s%s.csv', angle_suffix, res_tag));
        writetable(transmission_table, csv_name);
        fprintf('Saved %s with %d rows and %d wavelengths.\n', csv_name, size(S.trans,1), size(S.trans,2));
        
        % Plot
        f = figure('Position', [100 100 1200 800], 'Visible', 'off');
        hold on;
        for ii = 1:size(S.trans, 1)
            plot(S.wavelength, S.trans(ii, :), 'LineWidth', 1);
        end
        xlabel('Wavelength (\mum)', 'FontSize', 12);
        ylabel('Transmission', 'FontSize', 12);
        title(sprintf('All Circular Pillar Transmission Spectra — %s', key), 'FontSize', 14);
        grid on; ylim([0 1]); box on; hold off;
        
        png_name = fullfile(main_directory, sprintf('AllTransmissionSpectra_CircularPillars_%s%s.png', key, res_tag));
        fig_name = fullfile(main_directory, sprintf('AllTransmissionSpectra_CircularPillars_%s%s.fig', key, res_tag));
        
        saveas(f, png_name);
        saveas(f, fig_name);
        close(f);
    catch ME
        fprintf('Error processing %s: %s\n', key, ME.message);
    end
end

fprintf('Done. Processing complete in:\n%s\n', main_directory);

function add_to_theta_map(theta_map, theta_key, wavelength_values, row_block, name_block)
    if isKey(theta_map, theta_key)
        S = theta_map(theta_key);
        if length(S.wavelength) ~= length(wavelength_values)
            warning('Wavelength count mismatch for %s. Skipping.', theta_key);
        else
            S.trans = [S.trans; row_block];       
            S.names = [S.names, name_block];      
            theta_map(theta_key) = S;
        end
    else
        theta_map(theta_key) = struct( ...
            'wavelength', wavelength_values(:).', ...
            'trans', row_block, ...
            'names', {name_block});
    end
end