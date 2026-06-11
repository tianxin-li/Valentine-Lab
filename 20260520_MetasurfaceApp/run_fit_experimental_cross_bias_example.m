% RUN_FIT_EXPERIMENTAL_CROSS_BIAS_EXAMPLE
%
% Edit the paths and intended design values below, then run this script.
% The experimental file should have:
%   column 1 = wavelength (um or nm)
%   column 2 = measured transmission (0-1 or percent)

clear; clc;
addpath 'RCWA functions'/

experimental_file = "V:\SimulationData\Rahul\Hyperspectral Imaging Project\OpticsLab Experiment\Filter Characterization\Filter Bias Test\FilterExample.xlsx";
si_file = "V:\SimulationData\Rahul\Material Dielectric Function\Si_Penn_Extrapolated_260520.xlsx";

intended = struct();
intended.pitch = 1.150;          % um, held fixed during fitting
intended.width = 0.514;          % um, cross major width in the intended design
intended.aspect_ratio = 0.20;    % minor/major in the intended design
intended.height = 1.30;          % um
intended.h_cap = 0.030;          % um
intended.n_cap = 1.745;
intended.n_substrate = 1.45;
intended.theta = 0;              % deg
intended.pol = 'avg';            % 'TE', 'TM', or 'avg'
intended.si_file = si_file;

opts = struct();
opts.width_bias_nm = [-5 0];    % nm, relative to intended.width
opts.width_step_nm = 5;          % nm
opts.ar_bias = [-0.02 0];        % relative to intended.aspect_ratio
opts.ar_step = 0.01;
opts.wavelength_range = [0.9 1.64];
opts.nn = [1 1];
opts.make_plot = true;
opts.output_prefix = 'cross_bias_fit_example2';

result = fit_experimental_cross_bias(experimental_file, intended, opts);
disp(result.best);
