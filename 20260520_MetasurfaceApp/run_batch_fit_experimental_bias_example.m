
% RUN_BATCH_FIT_EXPERIMENTAL_BIAS_EXAMPLE
%
% Edit the paths below, then run this script overnight.
%
% Experimental Excel format:
%   row 1: wl, 11, 21, 31, 41, 12, ...
%   col 1: wavelength values
%   col 2+: measured transmission spectra
%
% Geometry Excel/text format:
%   one geometry label per row. Row 1 maps to experimental column 2.

clear; clc;
addpath 'RCWA functions'/

experimental_file = "V:\SimulationData\Rahul\Hyperspectral Imaging Project\OpticsLab Experiment\Filter Characterization\Filter Bias Test\052126_PennFilters.xlsx";
geometry_file = "V:\SimulationData\Rahul\Hyperspectral Imaging Project\OpticsLab Experiment\Filter Characterization\Filter Bias Test\FilterNames.xlsx";
si_file = 'V:\SimulationData\Rahul\Material Dielectric Function\Si_Penn_Extrapolated_260520.xlsx';

common = struct();
common.si_file = si_file;
common.h_cap = 0.030;
common.n_cap = 1.745;
common.n_substrate = 1.45;
common.theta = 0;
common.pol = 'avg';       % 'TE', 'TM', or 'avg'

opts = struct();
opts.output_root = fullfile('D:\Rahul\Metasurface\Bias Fit Results', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
opts.resume = true;

opts.fit = struct();
opts.fit.nn = [12 12];
opts.fit.wavelength_range = [1.00 1.64];
opts.fit.width_bias_nm = [-50 0];
opts.fit.width_step_nm = 5;
opts.fit.ar_bias = [-0.03 0];
opts.fit.ar_step = 0.01;
opts.fit.rmse_weight = 1.0;
opts.fit.global_dip_shift_weight = 3.0;

summary = batch_fit_experimental_bias(experimental_file, geometry_file, ...
    common, opts);
