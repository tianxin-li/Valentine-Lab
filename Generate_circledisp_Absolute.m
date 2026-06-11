clc; clearvars; close all
addpath('RCWA functions')
addpath('Library Data')

%% Parameters - All values are in absolute units
% height = (0.7:0.1:1.1); %%make it 0.5 to 3.5
height = 1.3;
h_cap = 0.03;

% pitch_s = (0.4:0.1:1.5); %%make it 1.5 to 3.5
pitch_s = (1.1:0.025:1.2); %%make it 1.5 to 3.5

waveband = "SWIR";

% Load material data
% data = readtable("/Volumes/ValentineLab/SimulationData/Rahul/Material Dielectric Function/Si_0.8_to_1.7_100pts.xlsx");
data = readtable("V:\SimulationData\Rahul\Material Dielectric Function\Si_Experimental_800to1700_100pts.xlsx");
% data = readtable("V:\SimulationData\Rahul\Material Dielectric Function\Si_2.5_to_5_100pts.xlsx");

n_background = 1;   % air
n_pillar = (data.n + 1j*data.k);

%%SWIR
n_substrate = 1.45; % Quartz
n_cap = 1.745;

% %%MWIR
% n_substrate = 1.65; % Quartz
% n_cap = 1.6;

wavelength = data.wl; 
num_wavelengths = length(wavelength);
min_wavelength = wavelength(1);
max_wavelength = wavelength(end);

%% Diameter parameters (absolute values)
num_diameter = 20;    

% pillar_type = "circle";
% pillar_type = "circle_hole";
pillar_type = 'circle_with_cap';


%%
wavelength = linspace(min_wavelength, max_wavelength, num_wavelengths);
wavelength_lim = [min_wavelength, max_wavelength, num_wavelengths];

trans_data = zeros(num_wavelengths, num_diameter, 2);
refl_data = trans_data;
trans_eff_data = zeros(num_wavelengths, num_diameter);
refl_eff_data = trans_eff_data;

%% RCWA Simulation
% angles = [0, 10, 20, 30, 40, 45, 50, 60];
angles = [0, 10, 20];

totalSteps = length(angles) * length(pitch_s) * length(height) * num_diameter * num_wavelengths;

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
        %% Diameter parameters (absolute values)
%         min_diameter = 0.20; %change to fabrication minimum
%         max_diameter = 0.75.*pitch;

        min_diameter = 0.20; %change to fabrication minimum
        max_diameter = 0.75.*pitch;
    
        diameter = linspace(min_diameter, max_diameter, num_diameter);
        diameter_lim = [min_diameter, max_diameter, num_diameter];

        for i = 1:length(height)
            h = height(i);
            h1 = h_cap;
            
            for j1 = 1:num_diameter
                w1 = diameter(j1);
                
                parfor k = 1:num_wavelengths
                    % Call RCWA with absolute values and pitch
                    % [trans, refl, trans_eff, refl_eff] = RCWA_bigcode_Absolute(wavelength(k), h, n_substrate, n_pillar(k), n_background, pillar_type, theta, pitch, w1);
                    [trans, refl, trans_eff, refl_eff] = RCWA_bigcode_Absolute(wavelength(k), h, n_substrate, n_pillar(k), n_background, pillar_type, theta, pitch, w1, h1, n_cap);

                    trans_data(k, j1, :) = [abs(trans) angle(trans)];
                    refl_data(k, j1, :) = [abs(refl) angle(refl)];
                    trans_eff_data(k, j1) = trans_eff;
                    refl_eff_data(k, j1) = refl_eff;
                    
                    % Send progress update
                    send(progressQueue, 1); 
                end
            end

            % Save the data
            note = "Generated with Reticolo, last update 09/2025\n" + ...
                "using modified non-normalized RCWA code.\n"; 

            WriteMat3(pillar_type, waveband, "um", "AmpPhase", pitch, h, ...
                "Material", "Si", "pillar", n_pillar, "Approximate value",...
                "Material", "SiO2", "substrate", n_substrate, "Quartz",...
                "Material", "air", "background", 1, "Air background",...
                "Param", "wavelength", wavelength_lim, "",...
                "Param", "diameter", diameter_lim, "diameter",...
                "Constant", "height", h, "",...
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