%% prepare_combined_averaged_library.m
% Combine TE/TM-averaged per-angle filter tables from multiple shape
% Averaged folders into one filter-selection-ready Excel file per angle.
%
% Output files:
%   TransmissionTable_ALL_theta0.xlsx
%   TransmissionTable_ALL_theta10.xlsx
%   TransmissionTable_ALL_theta20.xlsx
%
% Each output has:
%   column 1: FilterName
%   columns 2:end: transmission values interpolated to 64 wavelengths
%                  from 8000 to 14000 nm.

clearvars; clc;

appDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(appDir);

target_wavelength_nm = linspace(8000, 14000, 64);
angle_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
seen_names_by_angle = containers.Map('KeyType', 'char', 'ValueType', 'any');
selected_files = {};

default_start_folder = fullfile(projectDir, 'Library Data2');
if ~isfolder(default_start_folder)
    default_start_folder = pwd;
end

keep_adding = true;
while keep_adding
    averaged_folder = uigetdir(default_start_folder, ...
        'Select one shape Averaged folder');
    if isequal(averaged_folder, 0)
        if isempty(selected_files)
            fprintf('No Averaged folder selected. Nothing to do.\n');
            return;
        end
        break;
    end

    folder_files = find_angle_files_in_folder(averaged_folder);
    selected_files = [selected_files; folder_files(:)]; %#ok<AGROW>
    default_start_folder = fileparts(fileparts(averaged_folder));

    answer = questdlg('Do you want to add another shape Averaged folder?', ...
        'Add Another Shape?', 'Yes', 'No', 'Yes');
    keep_adding = strcmp(answer, 'Yes');
end

output_folder = uigetdir(default_start_folder, ...
    'Select output folder for combined angle files');
if isequal(output_folder, 0)
    fprintf('No output folder selected. Nothing to do.\n');
    return;
end

fprintf('Combining %d averaged table(s)...\n', numel(selected_files));

for ii = 1:numel(selected_files)
    file_path = selected_files{ii};
    [~, file_name, file_ext] = fileparts(file_path);
    display_name = [file_name file_ext];
    theta = parse_theta_from_filename(display_name);
    theta_key = sprintf('theta%d', theta);

    fprintf('  [%d/%d] %s -> %s\n', ii, numel(selected_files), ...
        file_path, theta_key);

    T = readtable(file_path, 'VariableNamingRule', 'preserve');
    if width(T) < 2
        warning('Skipping %s: expected FilterName plus spectral columns.', file_path);
        continue;
    end

    raw_names = string(T{:, 1});
    raw_names = strip(raw_names);
    spectra = table_to_numeric_matrix(T(:, 2:end));
    source_wavelength_nm = extract_wavelengths_from_headers( ...
        T.Properties.VariableNames(2:end), size(spectra, 2), target_wavelength_nm);

    spectra_64 = interpolate_spectra(source_wavelength_nm, spectra, target_wavelength_nm);
    if isKey(seen_names_by_angle, theta_key)
        seen_names = seen_names_by_angle(theta_key);
    else
        seen_names = containers.Map('KeyType', 'char', 'ValueType', 'double');
    end
    unique_names = make_unique_filter_names(raw_names, file_path, seen_names);
    seen_names_by_angle(theta_key) = seen_names;

    block = struct( ...
        'names', unique_names(:), ...
        'spectra', spectra_64);

    if isKey(angle_map, theta_key)
        old = angle_map(theta_key);
        old.names = [old.names; block.names];
        old.spectra = [old.spectra; block.spectra];
        angle_map(theta_key) = old;
    else
        angle_map(theta_key) = block;
    end
end

if angle_map.Count == 0
    error('No valid averaged files were loaded.');
end

expected_angle_keys = {'theta0', 'theta10', 'theta20'};
found_angle_keys = angle_map.keys;
missing_angle_keys = expected_angle_keys(~ismember(expected_angle_keys, found_angle_keys));
if ~isempty(missing_angle_keys)
    error('Missing required angle table(s): %s', strjoin(missing_angle_keys, ', '));
end

extra_angle_keys = setdiff(found_angle_keys, expected_angle_keys);
if ~isempty(extra_angle_keys)
    warning('Ignoring unsupported extra angle table(s): %s', ...
        strjoin(sort_angle_keys(extra_angle_keys), ', '));
end

angle_keys = expected_angle_keys;
out_paths = cell(1, numel(angle_keys));

for ii = 1:numel(angle_keys)
    theta_key = angle_keys{ii};
    block = angle_map(theta_key);

    header = [{'FilterName'}, arrayfun(@(w) sprintf('%.2f', w), ...
        target_wavelength_nm, 'UniformOutput', false)];
    body = [cellstr(block.names), num2cell(block.spectra)];
    out_cell = [header; body];

    out_path = fullfile(output_folder, sprintf('TransmissionTable_ALL_%s.xlsx', theta_key));
    writecell(out_cell, out_path);
    out_paths{ii} = out_path;

    fprintf('Saved %s  (%d filters, %d wavelengths)\n', ...
        out_path, size(block.spectra, 1), numel(target_wavelength_nm));
end

fprintf('\nDone. Combined files written to:\n  %s\n', output_folder);

%% Local helpers
function files = find_angle_files_in_folder(averaged_folder)
    if ~isfolder(averaged_folder)
        error('Not a valid folder: %s', averaged_folder);
    end

    expected_thetas = [0 10 20];
    files = cell(numel(expected_thetas), 1);

    for ii = 1:numel(expected_thetas)
        theta = expected_thetas(ii);
        pat = sprintf('*theta%d.*', theta);
        matches = [ ...
            dir(fullfile(averaged_folder, strrep(pat, '.*', '.csv'))); ...
            dir(fullfile(averaged_folder, strrep(pat, '.*', '.xlsx'))); ...
            dir(fullfile(averaged_folder, strrep(pat, '.*', '.xls'))) ...
        ];

        matches = matches(~[matches.isdir]);
        if isempty(matches)
            error('Missing theta%d averaged table in:\n  %s', theta, averaged_folder);
        end
        if numel(matches) > 1
            names = string({matches.name});
            [~, order] = sort(names);
            matches = matches(order);
            warning(['Multiple theta%d tables found in:\n  %s\n' ...
                'Using: %s'], theta, averaged_folder, matches(1).name);
        end

        files{ii} = fullfile(matches(1).folder, matches(1).name);
    end
end

function theta = parse_theta_from_filename(filename)
    tok = regexp(filename, 'theta\s*[_-]?(-?\d+)', 'tokens', 'once', ...
        'ignorecase');
    if isempty(tok)
        error('Could not parse theta angle from filename: %s', filename);
    end
    theta = str2double(tok{1});
    if isnan(theta)
        error('Invalid theta angle in filename: %s', filename);
    end
end

function numeric_data = table_to_numeric_matrix(T)
    raw = table2cell(T);
    numeric_data = nan(size(raw));
    for rr = 1:size(raw, 1)
        for cc = 1:size(raw, 2)
            val = raw{rr, cc};
            if isnumeric(val)
                numeric_data(rr, cc) = val;
            elseif islogical(val)
                numeric_data(rr, cc) = double(val);
            elseif ismissing(string(val))
                numeric_data(rr, cc) = NaN;
            else
                numeric_data(rr, cc) = str2double(string(val));
            end
        end
    end
end

function wl_nm = extract_wavelengths_from_headers(headers, n_cols, target_wavelength_nm)
    wl_nm = nan(1, n_cols);
    generic = false(1, n_cols);

    for jj = 1:n_cols
        h = string(headers{jj});
        h_clean = strtrim(h);

        if ~isempty(regexp(h_clean, '^(Wavelength|col)_?\d+$', 'once', ...
                'ignorecase'))
            generic(jj) = true;
            continue;
        end

        tok = regexp(h_clean, '[-+]?\d*\.?\d+', 'match', 'once');
        if ~isempty(tok)
            wl_nm(jj) = str2double(tok);
        end
    end

    if any(isnan(wl_nm)) || any(generic)
        wl_nm = linspace(target_wavelength_nm(1), target_wavelength_nm(end), n_cols);
        return;
    end

    % Header values below 20 are almost certainly micrometres.
    if max(wl_nm) < 20
        wl_nm = wl_nm * 1000;
    end
end

function spectra_64 = interpolate_spectra(source_wl_nm, spectra, target_wl_nm)
    [source_wl_nm, order] = sort(source_wl_nm(:).');
    spectra = spectra(:, order);

    [source_wl_nm, unique_idx] = unique(source_wl_nm, 'stable');
    spectra = spectra(:, unique_idx);

    if target_wl_nm(1) < source_wl_nm(1) || target_wl_nm(end) > source_wl_nm(end)
        warning(['Target range %.2f-%.2f nm extends outside source range ' ...
            '%.2f-%.2f nm. Edge values will be extrapolated.'], ...
            target_wl_nm(1), target_wl_nm(end), source_wl_nm(1), source_wl_nm(end));
    end

    spectra_64 = nan(size(spectra, 1), numel(target_wl_nm));
    for rr = 1:size(spectra, 1)
        y = spectra(rr, :);
        good = isfinite(source_wl_nm) & isfinite(y);
        if nnz(good) < 2
            continue;
        end
        spectra_64(rr, :) = interp1(source_wl_nm(good), y(good), ...
            target_wl_nm, 'linear', 'extrap');
    end
end

function unique_names = make_unique_filter_names(raw_names, filename, seen_names)
    [~, stem] = fileparts(filename);
    stem = regexprep(stem, '[^\w]+', '_');
    unique_names = strings(size(raw_names));

    for rr = 1:numel(raw_names)
        base = raw_names(rr);
        if strlength(base) == 0 || ismissing(base)
            base = "UnnamedFilter";
        end
        key = char(base);

        if isKey(seen_names, key)
            seen_names(key) = seen_names(key) + 1;
            unique_names(rr) = string(stem) + "__" + base;
        else
            seen_names(key) = 1;
            unique_names(rr) = base;
        end

        % If the prefixed name also collides, append a numeric suffix.
        final_key = char(unique_names(rr));
        while isKey(seen_names, final_key)
            if strcmp(final_key, key)
                break;
            end
            seen_names(final_key) = seen_names(final_key) + 1;
            unique_names(rr) = string(final_key) + "_" + string(seen_names(final_key));
            final_key = char(unique_names(rr));
        end
        if ~isKey(seen_names, final_key)
            seen_names(final_key) = 1;
        end
    end
end

function sorted_keys = sort_angle_keys(keys_in)
    theta_vals = nan(size(keys_in));
    for kk = 1:numel(keys_in)
        tok = regexp(keys_in{kk}, 'theta(-?\d+)', 'tokens', 'once');
        theta_vals(kk) = str2double(tok{1});
    end
    [~, order] = sort(theta_vals);
    sorted_keys = keys_in(order);
end
