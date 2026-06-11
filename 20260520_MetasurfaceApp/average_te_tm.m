function out_paths = average_te_tm(te_folder, tm_folder, output_folder, wavelengths)
% AVERAGE_TE_TM  Average matching TE and TM transmittance CSVs.
%
%   out_paths = average_te_tm(te_folder, tm_folder, output_folder, wavelengths)
%
%   Function version of the GetFilterTable_TE_TM_general script. Differences:
%       (1) Folders are passed in (no uigetdir prompts).
%       (2) 'wavelengths' (a numeric vector, in micrometres) is passed in so
%           the output column headers reflect the ACTUAL wavelength grid used
%           in the simulation, instead of a hardcoded 800:1700 nm / 100 pts.
%
%   Pairs CSV files by identical filename between te_folder and tm_folder,
%   averages their numeric columns element-wise (assumes the illumination is
%   50% TE / 50% TM), and writes the averaged tables into output_folder.
%
%   Returns a cell array of the averaged CSV paths that were written.

    if ~isfolder(te_folder)
        error('average_te_tm:badTE', 'TE folder not found: %s', te_folder);
    end
    if ~isfolder(tm_folder)
        error('average_te_tm:badTM', 'TM folder not found: %s', tm_folder);
    end
    if ~isfolder(output_folder)
        mkdir(output_folder);
    end

    csv_files = dir(fullfile(te_folder, '*.csv'));
    if isempty(csv_files)
        error('average_te_tm:noCSV', 'No .csv files found in %s', te_folder);
    end
    fprintf('Found %d CSV files to average.\n', numel(csv_files));

    % column headers from the real wavelength grid (convert um -> nm label)
    wl_nm = wavelengths(:).' * 1000;
    wavelength_headers = arrayfun(@(w) sprintf('%.2f_nm', w), wl_nm, ...
        'UniformOutput', false);

    out_paths = {};

    for i = 1:numel(csv_files)
        current_filename = csv_files(i).name;
        fprintf('Averaging: %s\n', current_filename);

        te_filepath = fullfile(te_folder, current_filename);
        tm_filepath = fullfile(tm_folder, current_filename);

        if ~exist(tm_filepath, 'file')
            warning('No matching TM file for "%s". Skipping.', current_filename);
            continue;
        end

        try
            te_table = readtable(te_filepath);
            tm_table = readtable(tm_filepath);

            filter_names_column = te_table(:, 1);

            numeric_data_TE = table2array(te_table(:, 2:end));
            numeric_data_TM = table2array(tm_table(:, 2:end));

            if ~isequal(size(numeric_data_TE), size(numeric_data_TM))
                warning(['TE/TM size mismatch for "%s" ' ...
                    '(TE %s vs TM %s). Skipping.'], current_filename, ...
                    mat2str(size(numeric_data_TE)), mat2str(size(numeric_data_TM)));
                continue;
            end

            averaged_data = (numeric_data_TE + numeric_data_TM) / 2;

            averaged_data_table = array2table(averaged_data);
            output_table = [filter_names_column, averaged_data_table];

            first_header = te_table.Properties.VariableNames{1};

            if numel(wavelength_headers) ~= size(averaged_data, 2)
                warning(['Wavelength vector length (%d) does not match CSV ' ...
                    'column count (%d) for "%s". Using generic headers.'], ...
                    numel(wavelength_headers), size(averaged_data,2), current_filename);
                hdrs = arrayfun(@(j) sprintf('col_%d', j), ...
                    1:size(averaged_data,2), 'UniformOutput', false);
            else
                hdrs = wavelength_headers;
            end
            output_table.Properties.VariableNames = [first_header, hdrs];

            output_filepath = fullfile(output_folder, current_filename);
            writetable(output_table, output_filepath);
            out_paths{end+1} = output_filepath; %#ok<AGROW>

        catch ME
            warning('Error processing "%s". Skipping. %s', ...
                current_filename, ME.message);
        end
    end

    fprintf('average_te_tm complete. Output in:\n  %s\n', output_folder);
end
