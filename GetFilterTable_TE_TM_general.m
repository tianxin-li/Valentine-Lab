% Script to Average Transmittance Data from TE and TM CSV Files

clc;

clearvars;

close all;

%% 1. User Input: Select TE and TM Data Folders

% --- DEFINE YOUR STARTING FOLDER HERE ---

% Replace this example path with your actual folder path

start_path_TE = 'V:\SimulationData\Rahul\Hyperspectral Imaging Project\Metasurface Library\Library Data';

fprintf('Select the folder containing the TE polarization data...\n');

te_folder = uigetdir(start_path_TE, 'Select Folder A: TE Polarization Data');

if isequal(te_folder, 0), disp('Operation cancelled by user.'); return; end

start_path_TM = "V:\SimulationData\Rahul\Hyperspectral Imaging Project\Metasurface Library\Library Data";

fprintf('Select the folder containing the TM polarization data...\n');

tm_folder = uigetdir(start_path_TM, 'Select Folder B: TM Polarization Data');

if isequal(tm_folder, 0), disp('Operation cancelled by user.'); return; end

start_path_combined = "V:\SimulationData\Rahul\Hyperspectral Imaging Project\Metasurface Library\Library Data\December 2025 Final Filters";

fprintf('Select a folder to save the averaged results...\n');

output_folder = uigetdir(start_path_combined, 'Select Output Folder');

if isequal(output_folder, 0), disp('Operation cancelled by user.'); return; end

%% 2. Find and Process Files

% Get a list of all CSV files in the TE folder.

csv_files = dir(fullfile(te_folder, '*.csv'));

if isempty(csv_files)

error('No .csv files were found in the selected TE folder.');

end

fprintf('\nFound %d CSV files to process.\n', length(csv_files));

% Loop through each file found in the TE folder.

for i = 1:length(csv_files)

current_filename = csv_files(i).name;

fprintf('Processing: %s\n', current_filename);


% Construct the full file paths for both TE and TM files.

te_filepath = fullfile(te_folder, current_filename);

tm_filepath = fullfile(tm_folder, current_filename);


% Check if the corresponding TM file exists before proceeding.

if ~exist(tm_filepath, 'file')

warning('Matching TM file not found for "%s". Skipping this file.', current_filename);

continue;

end


try

%% 3. Load Data from Both Files

% Use readtable to automatically handle headers and mixed data types.

te_table = readtable(te_filepath);

tm_table = readtable(tm_filepath);


%% 4. Extract and Average Data

% The first column contains the filter names (text).

filter_names_column = te_table(:, 1);


% The rest of the columns contain the numeric transmittance data.

numeric_data_TE = table2array(te_table(:, 2:end));

numeric_data_TM = table2array(tm_table(:, 2:end));


% Perform the element-wise average.

averaged_data = (numeric_data_TE + numeric_data_TM) / 2;


%% 5. Prepare the New Output Table

% Convert the averaged numeric data back to a table.

averaged_data_table = array2table(averaged_data);


% Combine the filter names column with the new averaged data.

output_table = [filter_names_column, averaged_data_table];


% --- Create New, Meaningful Headers ---

% Generate the 100 wavelength points from 800nm to 1700nm.

wavelengths = linspace(800, 1700, 100);


% Get the header for the first column (e.g., "Filter Name").

first_header = te_table.Properties.VariableNames{1};


% Create new headers for the wavelength columns (e.g., "800.00_nm").

wavelength_headers = arrayfun(@(w) sprintf('%.2f_nm', w), wavelengths, 'UniformOutput', false);


% Combine the headers and apply them to the output table.

output_table.Properties.VariableNames = [first_header, wavelength_headers];


%% 6. Save the Averaged File

% Construct the full path for the output file.

output_filepath = fullfile(output_folder, current_filename);


% Write the final table to a new CSV file.

writetable(output_table, output_filepath);


catch ME

warning('An error occurred while processing "%s". Skipping. Error: %s', current_filename, ME.message);

end

end

fprintf('\nProcessing complete. Averaged files are saved in:\n%s\n', output_folder);

