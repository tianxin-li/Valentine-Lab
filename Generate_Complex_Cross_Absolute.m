clc; clearvars; close all
addpath('RCWA functions')
addpath('Library Data')

%% Parameters - All values are Absolute (normalization happens in the loop)

% height = (0.5:0.1:1.5); %%make it 0.5 to 3.5
height = 1.3;   
h_cap = 0.030;

% %%MWIR
% height = 2.5;
% h_cap = 0.1;

% pitch_s = (2.5:0.1:3.5); %%make it 1.5 to 3.5
% pitch_s = 3.0;

pitch_s = (1.1:0.05:1.2); %%make it 1.5 to 3.5


waveband = "SWIR";

% Load material data
% data = readtable("/Volumes/ValentineLab/SimulationData/Rahul/Material Dielectric Function/Si_Experimental_800to1700_100pts.xlsx");
data = readtable("V:\SimulationData\Rahul\Material Dielectric Function\Si_Experimental_800to1700_100pts.xlsx");
% data = readtable("V:\SimulationData\Rahul\Material Dielectric Function\Si_2.5_to_5_100pts.xlsx");

n_background = 1;   % air
n_pillar = (data.n + 1j*data.k);
n_substrate = 1.45; % Quartz
n_cap = 1.745;

%%MWIR
% n_substrate = 1.65; % Quartz
% n_cap = 1.6;

wavelength = data.wl; 
num_wavelengths = length(wavelength);
min_wavelength = wavelength(1);
max_wavelength = wavelength(end);

%% Cross parameters Absolute Values
num_width = 13;    

% Aspect ratio for minor width (w2 = aspect_ratio * w1)
num_aspect = 3;
min_aspect = 0.2;
max_aspect = 0.4;

% min_aspect = 0.2;
% max_aspect = 0.2;

% pillar_type = "Complex_Cross_1";
pillar_type = "Complex_Cross_2";
% pillar_type = "Complex_Cross_3";



%%
wavelength = linspace(min_wavelength, max_wavelength, num_wavelengths);
wavelength_lim = [min_wavelength, max_wavelength, num_wavelengths];

aspect_ratio = linspace(min_aspect, max_aspect, num_aspect);
aspect_lim = [min_aspect, max_aspect, num_aspect];

trans_data = zeros(num_wavelengths, num_width, num_aspect, 2);
refl_data = trans_data;
trans_eff_data = zeros(num_wavelengths, num_width, num_aspect);
refl_eff_data = trans_eff_data;

%% RCWA Simulation
% angles = [0, 10, 20, 30];
angles = [0, 10, 20];

totalSteps = length(angles) * length(pitch_s) * length(height) * num_width * num_aspect * num_wavelengths;

% Create a parallel pool if not already open
if isempty(gcp('nocreate'))
    parpool;
end

% Create a data queue for progress updates
progressQueue = parallel.pool.DataQueue;

% Create a global variable to track progress
global progressCount
progressCount = 0;

% Set up a listener to update progress in real-time
afterEach(progressQueue, @(~) updateProgress(totalSteps));

% Main simulation loop
for angle_idx = 1:length(angles)
    theta = angles(angle_idx);
    
    for p = 1:length(pitch_s)
        pitch = pitch_s(p);
        min_width = 0.6;   
        max_width = 0.75*pitch;   
        width = linspace(min_width, max_width, num_width);
        width_lim = [min_width, max_width, num_width];
        
        for i = 1:length(height)
            h_label = height(i);
            h = height(i); 
            h1 = h_cap;

            for j1 = 1:num_width
                w1 = width(j1); 
                
                for j2 = 1:num_aspect
                    w2 = w1 * aspect_ratio(j2); % Minor width
                    w3 = w2;

                    parfor k = 1:num_wavelengths
                        % Call RCWA with cross parameters
                        [trans, refl, trans_eff, refl_eff] = RCWA_bigcode_Absolute((wavelength(k)), h, n_substrate, n_pillar(k), n_background, pillar_type, theta, pitch, w1, w2, w3, h1, n_cap);

                        trans_data(k, j1, j2, :) = [abs(trans) angle(trans)];
                        refl_data(k, j1, j2, :) = [abs(refl) angle(refl)];
                        trans_eff_data(k, j1, j2) = trans_eff;
                        refl_eff_data(k, j1, j2) = refl_eff;
                        
                        % Send progress update
                        send(progressQueue, 1); 
                    end
                end
            end

            % Save the data using WriteMatCross
            note = "Generated with Reticolo, last update 09/2025\n" + ...
                "using modified absolute cross RCWA code.\n";  

            WriteMatCross(pillar_type, waveband, "um", "AmpPhase", pitch, h_label, ...
                "Material", "Si", "pillar", n_pillar, "Approximate value",...
                "Material", "SiO2", "substrate", n_substrate, "Quartz",...
                "Material", "air", "background", 1, "Air background",...
                "Param", "wavelength", wavelength_lim, "",...
                "Param", "width", width_lim, "major width",...
                "Param", "aspect_ratio", aspect_lim, "minor_width/major_width ratio",...
                "Constant", "height", h_label, "",...
                "Constant", "theta", theta, "",...
                "Data", "transmission_bottom_0_0", trans_data, "[amp phase] of transmitted light",...
                "Data", "reflection_bottom_0_0", refl_data, "[amp phase] of 0 order reflected light",...
                "Data", "transmission_bottom_0_0_efficiency", trans_eff_data, "% of light intensity in 0 order transmission",...
                "Data", "reflection_bottom_0_0_efficiency", refl_eff_data, "% of light intensity in 0 order reflection",...
                "Creator", "Rahul Shah",...
                "Notes", note);
        end
    end
end

% Progress update function
function updateProgress(totalSteps)
    global progressCount
    progressCount = progressCount + 1;
    progressPercent = (progressCount / totalSteps) * 100;
    clc;
    fprintf('Overall Progress: %5.2f%%\n', progressPercent);
end