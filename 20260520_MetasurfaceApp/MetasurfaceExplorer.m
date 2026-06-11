function MetasurfaceExplorer()

appDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(appDir);
addpath(appDir);
rcwaDir = fullfile(projectDir, 'RCWA functions');
if exist(rcwaDir, 'dir'), addpath(rcwaDir); end
libraryDir = fullfile(projectDir, 'Library Data2');
if exist(libraryDir, 'dir'), addpath(libraryDir); end

% METASURFACE EXPLORER  Interactive tool for computing and visualising
%                       metasurface filter responses.
%
%   MetasurfaceExplorer()
%
%   TAB 1 — LIVE COMPUTE
%     Set shape and stack parameters, load the Si dispersion file, then:
%       • Compute a field profile at a chosen wavelength  (~5-15 s)
%       • Compute a full transmission spectrum             (~minutes)
%
%   TAB 2 — LIBRARY VIEWER
%     Browse a saved library folder, inspect stored spectra (all overlaid
%     or one at a time via sliders), and optionally compute a field
%     profile for any filter without re-entering parameters.
%
%   REQUIRES (all must be on the MATLAB path):
%     shape_registry, build_*_with_cap, RCWA_solve, compute_field,
%     read_matfile, RETICOLO (res0, res1, res2, res3, retio).

%% ======================================================================
%% SHARED STATE
%% ======================================================================
shapeList    = {};
currentSpec  = [];
prefGroup    = 'MetasurfaceExplorer';
livePrefName = 'LiveComputeLastUsed';
liveStartupPrefs = struct();

siFilePath   = '';
siWavelength = [];
siNPillar    = [];

liveField    = [];
liveSpectrum = struct('wavelength', [], 'efficiency', []);
liveSpectrumCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
liveDisplayedSpectrumKeys = {};
liveCancelRequested = false;
liveParallelFutures = parallel.FevalFuture.empty;

viewerFolder = '';
viewerFiles  = struct([]);
viewerInfo   = [];
viewerSpec   = [];
viewerField  = [];
viewerEntries = struct([]);
viewerDataset = [];

%% ======================================================================
%% UI HANDLE PRE-DECLARATIONS
%% ======================================================================
% CRITICAL: every UI control that is created in buildLiveTab or
% buildViewerTab but referenced in ANY other nested function (callbacks,
% initApp, helpers) must be declared here in the parent workspace.
% Without this MATLAB treats them as local variables in the builder
% function and they are invisible to all other nested functions.

% --- Live tab handles -------------------------------------------------
liveShapeDropdown        = [];
liveComponentDropdown    = [];
liveModelAxes            = [];
liveFieldAxes            = [];
liveSpectrumAxes         = [];
livePitchField           = [];
liveHeightField          = [];
liveHCapField            = [];
liveNCapField            = [];
liveNSubField            = [];
liveP1Label              = [];
liveP1Field              = [];
liveP2Label              = [];
liveP2Field              = [];
liveTaperMidLabel        = [];
liveTaperMidField        = [];
liveTaperBottomLabel     = [];
liveTaperBottomField     = [];
liveTaperSlicesLabel     = [];
liveTaperSlicesField     = [];
liveThetaField           = [];
liveWavelengthMinField   = [];
liveWavelengthMaxField   = [];
liveWavelengthSlider     = [];
liveWavelengthValueLabel = [];
livePolDropdown          = [];
liveComputeAnglesBtn     = [];
liveCancelBtn            = [];
liveClearSpectrumBtn     = [];
liveExportSpectrumBtn    = [];
liveNNField              = [];
liveSiLabel              = [];
liveComputeFieldBtn      = [];
liveComputeSpecBtn       = [];
liveStatusLabel          = [];

% --- Viewer tab handles -----------------------------------------------
viewerComponentDropdown    = [];
viewerModelAxes            = [];
viewerSpectrumAxes         = [];
viewerFieldAxes            = [];
viewerFolderLabel          = [];
viewerFileList             = [];
viewerInfoLabel            = [];
viewerP1Label              = [];
viewerP1ValueLabel         = [];
viewerP1Slider             = [];
viewerP2Label              = [];
viewerP2ValueLabel         = [];
viewerP2Slider             = [];
viewerWavelengthSlider     = [];
viewerWavelengthValueLabel = [];
viewerPolDropdown          = [];
viewerNNField              = [];
viewerComputeFieldBtn      = [];
viewerStatusLabel          = [];
viewerShowDropdown         = [];
viewerDataDropdown         = [];
viewerAngleDropdown        = [];
viewerExportSpectrumBtn    = [];

%% ======================================================================
%% CREATE WINDOW AND TABS
%% ======================================================================
fig = uifigure('Name', 'Metasurface Explorer', ...
    'Position', [30 30 1620 940], 'Resize', 'on');
fig.CloseRequestFcn = @appCloseRequested;

tg        = uitabgroup(fig, 'Position', [0 0 1620 940]);
liveTab   = uitab(tg, 'Title', '  Live Compute  ');
viewerTab = uitab(tg, 'Title', '  Library Viewer  ');

buildLiveTab();
buildViewerTab();
initApp();

%% ======================================================================
%% BUILD LIVE TAB
%% ======================================================================
    function buildLiveTab()

        lp = uipanel(liveTab, 'Title', 'Parameters', ...
            'Position', [5 5 355 905], ...
            'FontSize', 10, 'FontWeight', 'bold');

        % Component selector + axes
        uilabel(liveTab, 'Text', 'Display:', ...
            'Position', [370 912 65 22], 'FontWeight', 'bold');
        liveComponentDropdown = uidropdown(liveTab, ...
            'Items', {'|E|','|H|','Ex','Ey','Ez','Hx','Hy','Hz','Re(n)','Im(n)'}, ...
            'Value', '|E|', ...
            'Position', [440 912 140 25], ...
            'ValueChangedFcn', @liveComponentChanged);

        liveModelAxes = uiaxes(liveTab, 'Position', [370 490 605 440]);
        title(liveModelAxes, 'Unit Cell Model');
        xlabel(liveModelAxes, 'x (\mum)');
        ylabel(liveModelAxes, 'y (\mum)');
        zlabel(liveModelAxes, 'z (\mum)');
        grid(liveModelAxes, 'on');
        box(liveModelAxes, 'on');

        liveFieldAxes = uiaxes(liveTab, 'Position', [1000 490 605 440]);
        title(liveFieldAxes, 'Field Map — press Compute Field to populate');
        xlabel(liveFieldAxes, 'x (\mum)');
        ylabel(liveFieldAxes, 'z (\mum)');
        colorbar(liveFieldAxes);
        colormap(liveFieldAxes, 'hot');
        box(liveFieldAxes, 'on');

        liveSpectrumAxes = uiaxes(liveTab, 'Position', [370 30 1235 445]);
        title(liveSpectrumAxes, 'Transmission Spectrum — press Compute Spectrum to populate');
        xlabel(liveSpectrumAxes, 'Wavelength (\mum)');
        ylabel(liveSpectrumAxes, 'Efficiency (0-1)');
        ylim(liveSpectrumAxes, [0 1]);
        grid(liveSpectrumAxes, 'on');
        box(liveSpectrumAxes, 'on');

        % Layout constants
        row = 865; rs = 36; rh = 25;
        lx = 8; lw = 148; fx = 160; fw = 185;

        % STACK GEOMETRY
        secLabel(lp, 'STACK GEOMETRY', lx, row); row = row - rs;

        uilabel(lp, 'Text', 'Shape:', 'Position', [lx row lw 20]);
        liveShapeDropdown = uidropdown(lp, ...
            'Items', {}, ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveShapeChanged);
        row = row - rs;

        uilabel(lp, 'Text', 'Pitch (um):', 'Position', [lx row lw 20]);
        livePitchField = uieditfield(lp, 'numeric', ...
            'Value', 1.125, 'Limits', [0.05 20], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs;

        uilabel(lp, 'Text', 'Height (um):', 'Position', [lx row lw 20]);
        liveHeightField = uieditfield(lp, 'numeric', ...
            'Value', 1.3, 'Limits', [0.05 20], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs;

        uilabel(lp, 'Text', 'h_cap (um):', 'Position', [lx row lw 20]);
        liveHCapField = uieditfield(lp, 'numeric', ...
            'Value', 0.030, 'Limits', [0 5], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs;

        uilabel(lp, 'Text', 'n_cap:', 'Position', [lx row lw 20]);
        liveNCapField = uieditfield(lp, 'numeric', ...
            'Value', 1.745, 'Limits', [1 6], ...
            'Position', [fx row fw rh]);
        row = row - rs;

        uilabel(lp, 'Text', 'n_substrate:', 'Position', [lx row lw 20]);
        liveNSubField = uieditfield(lp, 'numeric', ...
            'Value', 1.45, 'Limits', [1 6], ...
            'Position', [fx row fw rh]);
        row = row - rs + 4;

        % GEOMETRIC PARAMETERS
        secLabel(lp, 'GEOMETRIC PARAMETERS', lx, row); row = row - rs;

        liveP1Label = uilabel(lp, 'Text', 'Diameter (um):', ...
            'Position', [lx row lw 20]);
        liveP1Field = uieditfield(lp, 'numeric', ...
            'Value', 0.450, 'Limits', [0.01 20], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs;

        liveP2Label = uilabel(lp, 'Text', 'Aspect Ratio:', ...
            'Position', [lx row lw 20]);
        liveP2Field = uieditfield(lp, 'numeric', ...
            'Value', 0.30, 'Limits', [0.01 1], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs + 4;

        liveTaperMidLabel = uilabel(lp, 'Text', 'Taper mid delta (um):', ...
            'Position', [lx row lw 20]);
        liveTaperMidField = uieditfield(lp, 'numeric', ...
            'Value', -0.020, 'Limits', [-20 20], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs;

        liveTaperBottomLabel = uilabel(lp, 'Text', 'Taper bottom delta:', ...
            'Position', [lx row lw 20]);
        liveTaperBottomField = uieditfield(lp, 'numeric', ...
            'Value', -0.060, 'Limits', [-20 20], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs;

        liveTaperSlicesLabel = uilabel(lp, 'Text', 'Taper slices:', ...
            'Position', [lx row lw 20]);
        liveTaperSlicesField = uieditfield(lp, 'numeric', ...
            'Value', 6, 'Limits', [2 100], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveGeometryChanged);
        row = row - rs + 4;

        % ILLUMINATION
        secLabel(lp, 'ILLUMINATION', lx, row); row = row - rs;

        uilabel(lp, 'Text', 'Theta (deg):', 'Position', [lx row lw 20]);
        liveThetaField = uieditfield(lp, 'numeric', ...
            'Value', 0, 'Limits', [0 89], ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @liveThetaChanged);
        row = row - rs;

        uilabel(lp, 'Text', 'WL min/max (um):', 'Position', [lx row lw 20]);
        liveWavelengthMinField = uieditfield(lp, 'numeric', ...
            'Value', 0.8, 'Limits', [0.01 100], ...
            'Position', [fx row 85 rh], ...
            'ValueChangedFcn', @liveWavelengthRangeChanged);
        liveWavelengthMaxField = uieditfield(lp, 'numeric', ...
            'Value', 1.7, 'Limits', [0.01 100], ...
            'Position', [fx+100 row 85 rh], ...
            'ValueChangedFcn', @liveWavelengthRangeChanged);
        row = row - rs;

        uilabel(lp, 'Text', 'Wavelength (um):', 'Position', [lx row lw 20]);
        liveWavelengthValueLabel = uilabel(lp, 'Text', '— load Si file first', ...
            'Position', [fx row fw 20], 'HorizontalAlignment', 'right');
        row = row - 28;

        liveWavelengthSlider = uislider(lp, ...
            'Limits', [1 2], 'Value', 1, ...
            'Position', [lx row 335 3], ...
            'MajorTicks', [], 'MinorTicks', [], ...
            'ValueChangedFcn',  @liveWavelengthChanged, ...
            'ValueChangingFcn', @liveWavelengthChanging);
        row = row - 32;

        uilabel(lp, 'Text', 'Polarization:', 'Position', [lx row lw 20]);
        livePolDropdown = uidropdown(lp, ...
            'Items', {'TE (+1)', 'TM (-1)', 'Average TE/TM'}, ...
            'Value', 'TE (+1)', ...
            'ValueChangedFcn', @liveSpectrumModeChanged, ...
            'Position', [fx row fw rh]);
        row = row - rs;

        uilabel(lp, 'Text', 'nn  [nx  ny]:', 'Position', [lx row lw 20]);
        liveNNField = uieditfield(lp, 'text', 'Value', '12  12', ...
            'Position', [fx row fw rh]);
        row = row - rs + 4;

        % PILLAR MATERIAL
        secLabel(lp, 'PILLAR MATERIAL  (Si)', lx, row); row = row - rs;

        uibutton(lp, 'Text', 'Load Si File...', ...
            'Position', [lx row 148 rh], ...
            'ButtonPushedFcn', @liveSiBrowse);
        liveSiLabel = uilabel(lp, 'Text', 'Searching default path...', ...
            'Position', [lx row-24 335 22], ...
            'FontSize', 8, 'FontColor', [0.45 0.45 0.45], 'WordWrap', 'on');
        row = row - 58;

        % COMPUTE
        secLabel(lp, 'COMPUTE', lx, row); row = row - rs;

        liveComputeFieldBtn = uibutton(lp, ...
            'Text', 'Compute Field  (current wavelength)', ...
            'Position', [lx row 335 rh+3], ...
            'BackgroundColor', [0.18 0.52 0.28], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @liveComputeField);
        row = row - rs + 2;

        liveComputeSpecBtn = uibutton(lp, ...
            'Text', 'Compute Spectrum  (all wavelengths)', ...
            'Position', [lx row 335 rh+3], ...
            'BackgroundColor', [0.18 0.38 0.62], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @liveComputeSpectrum);
        row = row - 55;

        liveComputeAnglesBtn = uibutton(lp, ...
            'Text', 'Compute 0 / 10 / 20 deg', ...
            'Position', [lx row 335 rh+3], ...
            'BackgroundColor', [0.34 0.32 0.56], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @liveComputeAngleSet);
        row = row - 40;

        liveCancelBtn = uibutton(liveTab, ...
            'Text', 'Cancel Current Simulation', ...
            'Position', [860 912 180 25], ...
            'BackgroundColor', [0.70 0.24 0.20], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'Enable', 'off', ...
            'ButtonPushedFcn', @liveCancelSimulation);

        liveClearSpectrumBtn = uibutton(liveTab, ...
            'Text', 'Clear Spectrum', ...
            'Position', [590 912 125 25], ...
            'BackgroundColor', [0.42 0.42 0.42], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @liveClearSpectrumGraph);

        liveExportSpectrumBtn = uibutton(liveTab, ...
            'Text', 'Export Spectrum', ...
            'Position', [725 912 125 25], ...
            'BackgroundColor', [0.20 0.45 0.62], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @liveExportSpectrumExcel);

        liveStatusLabel = uilabel(liveTab, 'Text', 'Ready.', ...
            'Position', [1050 912 545 22], ...
            'FontSize', 9, 'FontColor', [0.35 0.35 0.35], 'WordWrap', 'on');
    end

%% ======================================================================
%% BUILD VIEWER TAB
%% ======================================================================
    function buildViewerTab()

        vp = uipanel(viewerTab, 'Title', 'Library Browser', ...
            'Position', [5 5 355 905], ...
            'FontSize', 10, 'FontWeight', 'bold');

        uilabel(viewerTab, 'Text', 'Field display:', ...
            'Position', [370 912 85 22], 'FontWeight', 'bold');
        viewerComponentDropdown = uidropdown(viewerTab, ...
            'Items', {'|E|','|H|','Ex','Ey','Ez','Hx','Hy','Hz','Re(n)','Im(n)'}, ...
            'Value', '|E|', ...
            'Position', [460 912 140 25], ...
            'ValueChangedFcn', @viewerComponentChanged);

        viewerExportSpectrumBtn = uibutton(viewerTab, ...
            'Text', 'Export Spectrum', ...
            'Position', [610 912 150 25], ...
            'BackgroundColor', [0.20 0.45 0.62], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @viewerExportSpectrumExcel);

        viewerModelAxes = uiaxes(viewerTab, 'Position', [370 490 605 440]);
        title(viewerModelAxes, 'Unit Cell Model');
        xlabel(viewerModelAxes, 'x (\mum)');
        ylabel(viewerModelAxes, 'y (\mum)');
        zlabel(viewerModelAxes, 'z (\mum)');
        grid(viewerModelAxes, 'on');
        box(viewerModelAxes, 'on');

        viewerSpectrumAxes = uiaxes(viewerTab, 'Position', [370 30 1235 445]);
        title(viewerSpectrumAxes, 'Transmission Spectra — load a folder to begin');
        xlabel(viewerSpectrumAxes, 'Wavelength (\mum)');
        ylabel(viewerSpectrumAxes, 'Efficiency (0-1)');
        ylim(viewerSpectrumAxes, [0 1]);
        grid(viewerSpectrumAxes, 'on');
        box(viewerSpectrumAxes, 'on');

        viewerFieldAxes = uiaxes(viewerTab, 'Position', [1000 490 605 440]);
        title(viewerFieldAxes, 'Field Map — press "Compute Field" to populate');
        xlabel(viewerFieldAxes, 'x (\mum)');
        ylabel(viewerFieldAxes, 'z (\mum)');
        colorbar(viewerFieldAxes);
        colormap(viewerFieldAxes, 'hot');
        box(viewerFieldAxes, 'on');

        row = 865; rs = 36; rh = 25;
        lx = 8; lw = 148; fx = 160; fw = 185;

        % LIBRARY FOLDER
        secLabel(vp, 'LIBRARY FOLDER', lx, row); row = row - rs;

        uibutton(vp, 'Text', 'Browse Folder...', ...
            'Position', [lx row 148 rh], ...
            'ButtonPushedFcn', @viewerBrowseFolder);
        viewerFolderLabel = uilabel(vp, 'Text', 'No folder selected', ...
            'Position', [lx row-24 335 22], ...
            'FontSize', 8, 'FontColor', [0.45 0.45 0.45], 'WordWrap', 'on');
        row = row - 58;

        uilabel(vp, 'Text', 'Files:', 'Position', [lx row lw 20], ...
            'FontWeight', 'bold');
        row = row - 3;

        viewerFileList = uilistbox(vp, ...
            'Items', {}, ...
            'Position', [lx row-162 335 165], ...
            'ValueChangedFcn', @viewerFileSelected);
        row = row - 170;

        viewerInfoLabel = uilabel(vp, 'Text', '', ...
            'Position', [lx row 335 48], ...
            'FontSize', 8.5, 'WordWrap', 'on');
        row = row - 55;

        % FILTER SELECTION
        secLabel(vp, 'FILTER SELECTION', lx, row); row = row - rs;

        viewerP1Label = uilabel(vp, 'Text', 'P1 index:', ...
            'Position', [lx row lw 20]);
        viewerP1ValueLabel = uilabel(vp, 'Text', '—', ...
            'Position', [fx row fw 20], 'HorizontalAlignment', 'right');
        row = row - 28;

        viewerP1Slider = uislider(vp, ...
            'Limits', [1 2], 'Value', 1, ...
            'Position', [lx row 335 3], ...
            'MajorTicks', [], 'MinorTicks', [], ...
            'ValueChangedFcn',  @viewerP1Changed, ...
            'ValueChangingFcn', @viewerP1Changing);
        row = row - 32;

        viewerP2Label = uilabel(vp, 'Text', 'P2 (AR) index:', ...
            'Position', [lx row lw 20]);
        viewerP2ValueLabel = uilabel(vp, 'Text', '—', ...
            'Position', [fx row fw 20], 'HorizontalAlignment', 'right');
        row = row - 28;

        viewerP2Slider = uislider(vp, ...
            'Limits', [1 2], 'Value', 1, ...
            'Position', [lx row 335 3], ...
            'MajorTicks', [], 'MinorTicks', [], ...
            'ValueChangedFcn',  @viewerP2Changed, ...
            'ValueChangingFcn', @viewerP2Changing);
        row = row - 36;

        % SPECTRUM DISPLAY
        secLabel(vp, 'SPECTRUM DISPLAY', lx, row); row = row - rs;

        uilabel(vp, 'Text', 'Show mode:', 'Position', [lx row lw 20]);
        viewerShowDropdown = uidropdown(vp, ...
            'Items', {'All Angles', 'Selected Angle Only'}, ...
            'Value', 'All Angles', ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @viewerShowModeChanged);
        row = row - rs;

        uilabel(vp, 'Text', 'Data:', 'Position', [lx row lw 20]);
        viewerDataDropdown = uidropdown(vp, ...
            'Items', {'TE', 'TM', 'Average TE/TM'}, ...
            'Value', 'TE', ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @viewerDataModeChanged);
        row = row - rs;

        uilabel(vp, 'Text', 'Angle:', 'Position', [lx row lw 20]);
        viewerAngleDropdown = uidropdown(vp, ...
            'Items', {'theta = 0 deg'}, ...
            'ItemsData', {0}, ...
            'Value', 0, ...
            'Position', [fx row fw rh], ...
            'ValueChangedFcn', @viewerAngleChanged);
        row = row - rs + 4;

        % FIELD COMPUTATION
        secLabel(vp, 'FIELD COMPUTATION', lx, row); row = row - rs;

        uilabel(vp, 'Text', 'Polarization:', 'Position', [lx row lw 20]);
        viewerPolDropdown = uidropdown(vp, ...
            'Items', {'TE (+1)', 'TM (-1)'}, 'Value', 'TE (+1)', ...
            'Position', [fx row fw rh]);
        row = row - rs;

        uilabel(vp, 'Text', 'Wavelength (um):', 'Position', [lx row lw 20]);
        viewerWavelengthValueLabel = uilabel(vp, 'Text', '—', ...
            'Position', [fx row fw 20], 'HorizontalAlignment', 'right');
        row = row - 28;

        viewerWavelengthSlider = uislider(vp, ...
            'Limits', [1 2], 'Value', 1, ...
            'Position', [lx row 335 3], ...
            'MajorTicks', [], 'MinorTicks', [], ...
            'ValueChangedFcn',  @viewerWavelengthChanged, ...
            'ValueChangingFcn', @viewerWavelengthChanging);
        row = row - 32;

        uilabel(vp, 'Text', 'nn  [nx  ny]:', 'Position', [lx row lw 20]);
        viewerNNField = uieditfield(vp, 'text', 'Value', '12  12', ...
            'Position', [fx row fw rh]);
        row = row - rs;

        viewerComputeFieldBtn = uibutton(vp, ...
            'Text', 'Compute Field for Selected Filter', ...
            'Position', [lx row 335 rh+3], ...
            'BackgroundColor', [0.18 0.52 0.28], ...
            'FontColor', 'white', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @viewerComputeField);
        row = row - 55;

        viewerStatusLabel = uilabel(vp, 'Text', 'Load a folder to begin.', ...
            'Position', [lx row 335 48], ...
            'FontSize', 9, 'FontColor', [0.35 0.35 0.35], 'WordWrap', 'on');
    end

%% ======================================================================
%% STARTUP
%% ======================================================================
    function initApp()
        % Populate shape dropdown
        names        = shape_registry();
        displayNames = cell(size(names));
        for ii = 1:numel(names)
            s = shape_registry(names{ii});
            displayNames{ii} = s.display_name;
        end
        shapeList = names;

        liveShapeDropdown.Items     = displayNames;
        liveShapeDropdown.ItemsData = names;
        liveShapeDropdown.Value     = names{1};

        currentSpec = shape_registry(names{1});
        liveStartupPrefs = restoreLivePrefs();
        if isfield(liveStartupPrefs, 'shape') && ...
                any(strcmp(liveStartupPrefs.shape, names))
            liveShapeDropdown.Value = liveStartupPrefs.shape;
            currentSpec = shape_registry(liveStartupPrefs.shape);
        end
        currentSpec = applyLiveTaperOptions(currentSpec);
        updateLiveParamLabels();
        updateLiveModelAxes();

        % Try the last-used Si file first, then fall back to the default path.
        defaultSi = fullfile(projectDir, 'Material Dielectric Function', ...
            'Si_LWIR_8to14.xlsx');

        siToLoad = defaultSi;
        if isfield(liveStartupPrefs, 'si_file') && ...
                exist(liveStartupPrefs.si_file, 'file')
            siToLoad = liveStartupPrefs.si_file;
        end

        if exist(siToLoad, 'file')
            loadSiFile(siToLoad);
            restoreLiveWavelengthSelection(liveStartupPrefs);
        else
            liveSiLabel.Text      = 'Default Si file not found — use "Load Si File"';
            liveSiLabel.FontColor = [0.75 0.30 0.10];
        end
    end

    function prefs = restoreLivePrefs()
        prefs = struct();
        if ~ispref(prefGroup, livePrefName)
            return;
        end

        try
            prefs = getpref(prefGroup, livePrefName);
            setNumericIfPresent(livePitchField, prefs, 'pitch');
            setNumericIfPresent(liveHeightField, prefs, 'height');
            setNumericIfPresent(liveHCapField, prefs, 'h_cap');
            setNumericIfPresent(liveNCapField, prefs, 'n_cap');
            setNumericIfPresent(liveNSubField, prefs, 'n_substrate');
            setNumericIfPresent(liveP1Field, prefs, 'p1');
            setNumericIfPresent(liveP2Field, prefs, 'p2');
            setNumericIfPresent(liveTaperMidField, prefs, 'taper_mid_delta');
            setNumericIfPresent(liveTaperBottomField, prefs, 'taper_bottom_delta');
            setNumericIfPresent(liveTaperSlicesField, prefs, 'taper_num_slices');
            setNumericIfPresent(liveThetaField, prefs, 'theta');
            setNumericIfPresent(liveWavelengthMinField, prefs, 'wl_min');
            setNumericIfPresent(liveWavelengthMaxField, prefs, 'wl_max');

            if isfield(prefs, 'pol') && any(strcmp(prefs.pol, livePolDropdown.Items))
                livePolDropdown.Value = prefs.pol;
            end
            if isfield(prefs, 'field_component') && ...
                    any(strcmp(prefs.field_component, liveComponentDropdown.Items))
                liveComponentDropdown.Value = prefs.field_component;
            end
            if isfield(prefs, 'nn_text')
                liveNNField.Value = prefs.nn_text;
            end
        catch
            prefs = struct();
        end
    end

    function restoreLiveWavelengthSelection(prefs)
        if isempty(siWavelength) || ~isfield(prefs, 'selected_wavelength')
            return;
        end
        [~, idx] = min(abs(siWavelength - prefs.selected_wavelength));
        liveWavelengthSlider.Value = idx;
        updateLiveWavelengthLabel(idx);
    end

    function setNumericIfPresent(ctrl, prefs, fieldName)
        if isfield(prefs, fieldName) && isnumeric(prefs.(fieldName)) && ...
                isfinite(prefs.(fieldName))
            ctrl.Value = prefs.(fieldName);
        end
    end

    function saveLivePrefs()
        prefs = struct();
        try
            prefs.shape = liveShapeDropdown.Value;
            prefs.pitch = livePitchField.Value;
            prefs.height = liveHeightField.Value;
            prefs.h_cap = liveHCapField.Value;
            prefs.n_cap = liveNCapField.Value;
            prefs.n_substrate = liveNSubField.Value;
            prefs.p1 = liveP1Field.Value;
            prefs.p2 = liveP2Field.Value;
            prefs.taper_mid_delta = liveTaperMidField.Value;
            prefs.taper_bottom_delta = liveTaperBottomField.Value;
            prefs.taper_num_slices = liveTaperSlicesField.Value;
            prefs.theta = liveThetaField.Value;
            prefs.wl_min = liveWavelengthMinField.Value;
            prefs.wl_max = liveWavelengthMaxField.Value;
            prefs.pol = livePolDropdown.Value;
            prefs.field_component = liveComponentDropdown.Value;
            prefs.nn_text = liveNNField.Value;
            prefs.si_file = siFilePath;
            if ~isempty(siWavelength)
                idx = clampIdx(liveWavelengthSlider.Value, numel(siWavelength));
                prefs.selected_wavelength = siWavelength(idx);
            end
            setpref(prefGroup, livePrefName, prefs);
        catch
        end
    end

    function appCloseRequested(~, ~)
        saveLivePrefs();
        delete(fig);
    end

    function loadSiFile(filepath)
        try
            d               = readtable(filepath);
            rawWavelength   = d.wl(:).';
            rawNPillar      = (d.n(:) + 1j*d.k(:)).';
            wlMin           = liveWavelengthMinField.Value;
            wlMax           = liveWavelengthMaxField.Value;
            [siWavelength, siNPillar] = makeWavelengthWindow( ...
                rawWavelength, rawNPillar, wlMin, wlMax);
            Nw              = numel(siWavelength);
            siFilePath      = filepath;

            [~, fn, ext]    = fileparts(filepath);
            liveSiLabel.Text      = sprintf('Loaded: %s%s  (%d pts, %.3f\x2013%.3f \xB5m)', ...
                fn, ext, Nw, siWavelength(1), siWavelength(end));
            liveSiLabel.FontColor = [0.10 0.45 0.15];

            liveWavelengthSlider.Limits = [1 Nw];
            liveWavelengthSlider.Value  = round(Nw / 2);
            updateLiveWavelengthLabel(round(Nw / 2));
            setStatus(liveStatusLabel, sprintf('Si file loaded. %d wavelength points.', Nw));
            saveLivePrefs();
        catch ME
            liveSiLabel.Text      = ['Load error: ' ME.message];
            liveSiLabel.FontColor = [0.75 0.10 0.10];
            uialert(fig, ME.message, 'Invalid Wavelength Range');
        end
    end

    function [wl, nvals] = makeWavelengthWindow(rawWl, rawN, wlMin, wlMax)
        fileMin = min(rawWl);
        fileMax = max(rawWl);
        if wlMin >= wlMax
            error('MetasurfaceExplorer:badWavelengthRange', ...
                'Wavelength minimum must be smaller than maximum.');
        end
        if wlMin < fileMin || wlMax > fileMax
            error('MetasurfaceExplorer:wavelengthOutOfRange', ...
                ['Requested wavelength range %.4f-%.4f um is outside the Si file range ' ...
                '%.4f-%.4f um.'], wlMin, wlMax, fileMin, fileMax);
        end

        inRange = rawWl >= wlMin & rawWl <= wlMax;
        Nw = max(2, nnz(inRange));
        wl = linspace(wlMin, wlMax, Nw);
        nvals = interp1(rawWl, rawN, wl, 'pchip');
    end

    function updateLiveParamLabels()
        if isempty(currentSpec), return; end
        liveP1Label.Text = [currentSpec.param1_label ':'];
        if currentSpec.n_geom_params == 2
            liveP2Label.Text    = [currentSpec.param2_label ':'];
            liveP2Label.Visible = 'on';
            liveP2Field.Visible = 'on';
        else
            liveP2Label.Visible = 'off';
            liveP2Field.Visible = 'off';
        end
        isTaper = isTaperedShape(currentSpec);
        vis = ternaryOnOff(isTaper);
        liveTaperMidLabel.Visible = vis;
        liveTaperMidField.Visible = vis;
        liveTaperBottomLabel.Visible = vis;
        liveTaperBottomField.Visible = vis;
        liveTaperSlicesLabel.Visible = vis;
        liveTaperSlicesField.Visible = vis;
    end

    function updateLiveWavelengthLabel(idx)
        if isempty(siWavelength), return; end
        idx = clampIdx(idx, numel(siWavelength));
        liveWavelengthValueLabel.Text = sprintf('%.4f \xB5m', siWavelength(idx));
    end

%% ======================================================================
%% LIVE TAB CALLBACKS
%% ======================================================================
    function liveShapeChanged(~, ~)
        currentSpec = shape_registry(liveShapeDropdown.Value);
        currentSpec = applyLiveTaperOptions(currentSpec);
        updateLiveParamLabels();
        updateLiveModelAxes();
        saveLivePrefs();
    end

    function liveGeometryChanged(~, ~)
        updateLiveModelAxes();
        saveLivePrefs();
    end

    function liveThetaChanged(~, ~)
        saveLivePrefs();
    end

    function liveSpectrumModeChanged(~, ~)
        saveLivePrefs();
    end

    function liveSiBrowse(~, ~)
        start = siFilePath;
        if isempty(start), start = pwd; end
        [f, p] = uigetfile( ...
            {'*.xlsx;*.xls','Excel Files';'*.*','All Files'}, ...
            'Select Si refractive index file', start);
        if isequal(f, 0), return; end
        loadSiFile(fullfile(p, f));
    end

    function liveWavelengthChanged(~, event)
        updateLiveWavelengthLabel(event.Value);
        saveLivePrefs();
    end

    function liveWavelengthChanging(~, event)
        updateLiveWavelengthLabel(event.Value);
    end

    function liveWavelengthRangeChanged(~, ~)
        if ~isempty(siFilePath)
            loadSiFile(siFilePath);
        end
        saveLivePrefs();
    end

    function liveComponentChanged(~, ~)
        if ~isempty(liveField), updateLiveFieldAxes(); end
        saveLivePrefs();
    end

    function liveCancelSimulation(~, ~)
        liveCancelRequested = true;
        if ~isempty(liveParallelFutures)
            cancel(liveParallelFutures);
        end
        setStatus(liveStatusLabel, ...
            'Cancel requested. Stopping outstanding wavelength jobs...');
    end

    function liveClearSpectrumGraph(~, ~)
        liveSpectrum = struct('wavelength', [], 'efficiency', []);
        liveDisplayedSpectrumKeys = {};
        resetLiveSpectrumAxes('Transmission Spectrum - cleared');
        drawnow;
        setStatus(liveStatusLabel, 'Spectrum graph cleared.');
    end

    function liveExportSpectrumExcel(~, ~)
        exportSpectrumAxesToExcel(liveSpectrumAxes, liveStatusLabel, ...
            'live_spectrum_export.xlsx');
    end

    % -------------------------------------------------------------------
    function liveComputeField(~, ~)
        if isempty(currentSpec)
            setStatus(liveStatusLabel, 'Select a shape first.'); return; end
        if isempty(siWavelength)
            setStatus(liveStatusLabel, 'Load Si material file first.'); return; end
        if strcmp(livePolDropdown.Value, 'Average TE/TM')
            setStatus(liveStatusLabel, ...
                'Field maps need a single polarization. Choose TE or TM for Compute Field.');
            return;
        end

        try
            p = gatherLiveParams();
        catch ME
            setStatus(liveStatusLabel, ['Parameter error: ' ME.message]); return;
        end

        setStatus(liveStatusLabel, ...
            sprintf('Computing field at %.4f \xB5m ...', p.wl));
        beginLiveSimulation();
        drawnow;

        try
            checkLiveCancel();
            liveField = compute_field(currentSpec, p.wl, p.h, ...
                p.ns, p.np, 1, p.nc, p.theta, ...
                p.pitch, p.p1, p.p2, p.hc, p.pol, p.nn);
            checkLiveCancel();
            updateLiveFieldAxes();
            setStatus(liveStatusLabel, ...
                sprintf('Field ready (\x03BB = %.4f \xB5m, pol=%s).', ...
                p.wl, livePolDropdown.Value));
        catch ME
            if strcmp(ME.identifier, 'MetasurfaceExplorer:cancelled')
                setStatus(liveStatusLabel, 'Field simulation cancelled.');
            else
                setStatus(liveStatusLabel, ['Compute error: ' ME.message]);
            end
        end
        endLiveSimulation();
    end

    % -------------------------------------------------------------------
    function liveComputeSpectrum(~, ~)
        if isempty(currentSpec)
            setStatus(liveStatusLabel, 'Select a shape first.'); return; end
        if isempty(siWavelength)
            setStatus(liveStatusLabel, 'Load Si material file first.'); return; end

        try
            p = gatherLiveParams();
        catch ME
            setStatus(liveStatusLabel, ['Parameter error: ' ME.message]); return;
        end

        modeLabel = liveSpectrumModeLabel();

        beginLiveSimulation();

        try
            [rec, cacheKey] = getOrComputeLiveSpectrum(p, modeLabel, p.theta, true);
            liveSpectrum.wavelength = rec.wavelength;
            liveSpectrum.efficiency = rec.efficiency;
            addLiveDisplayedSpectrum(cacheKey);
            refreshLiveSpectrumPlot();
            setStatus(liveStatusLabel, sprintf( ...
                'Spectrum ready: %s theta=%g deg. Cached spectra: %d.', ...
                modeLabel, p.theta, liveSpectrumCache.Count));
        catch ME
            if strcmp(ME.identifier, 'MetasurfaceExplorer:cancelled')
                setStatus(liveStatusLabel, 'Spectrum simulation cancelled.');
            else
                setStatus(liveStatusLabel, ...
                    sprintf('Spectrum error: %s', ME.message));
            end
        end

        endLiveSimulation();
    end

    % -------------------------------------------------------------------
    function liveComputeAngleSet(~, ~)
        if isempty(currentSpec)
            setStatus(liveStatusLabel, 'Select a shape first.'); return; end
        if isempty(siWavelength)
            setStatus(liveStatusLabel, 'Load Si material file first.'); return; end

        try
            p = gatherLiveParams();
        catch ME
            setStatus(liveStatusLabel, ['Parameter error: ' ME.message]); return;
        end

        modeLabel = liveSpectrumModeLabel();
        angles = [0 10 20];
        oldTheta = liveThetaField.Value;

        beginLiveSimulation();

        try
            for ai = 1:numel(angles)
                checkLiveCancel();
                theta = angles(ai);
                liveThetaField.Value = theta;
                p.theta = theta;
                [rec, cacheKey] = getOrComputeLiveSpectrum(p, modeLabel, theta, true);
                liveSpectrum.wavelength = rec.wavelength;
                liveSpectrum.efficiency = rec.efficiency;
                addLiveDisplayedSpectrum(cacheKey);
                refreshLiveSpectrumPlot();
                drawnow;
            end
            liveThetaField.Value = oldTheta;
            p.theta = oldTheta;
            refreshLiveSpectrumPlot();
            setStatus(liveStatusLabel, sprintf( ...
                'Angle set ready for %s. Cached spectra: %d.', ...
                modeLabel, liveSpectrumCache.Count));
        catch ME
            liveThetaField.Value = oldTheta;
            p.theta = oldTheta;
            refreshLiveSpectrumPlot();
            if strcmp(ME.identifier, 'MetasurfaceExplorer:cancelled')
                setStatus(liveStatusLabel, 'Angle-set simulation cancelled.');
            else
                setStatus(liveStatusLabel, sprintf('Angle-set error: %s', ME.message));
            end
        end

        endLiveSimulation();
    end

    function beginLiveSimulation()
        liveCancelRequested = false;
        liveComputeSpecBtn.Enable  = 'off';
        liveComputeFieldBtn.Enable = 'off';
        liveComputeAnglesBtn.Enable = 'off';
        liveCancelBtn.Enable = 'on';
        drawnow;
    end

    function endLiveSimulation()
        liveComputeSpecBtn.Enable  = 'on';
        liveComputeFieldBtn.Enable = 'on';
        liveComputeAnglesBtn.Enable = 'on';
        liveCancelBtn.Enable = 'off';
        liveParallelFutures = parallel.FevalFuture.empty;
        liveCancelRequested = false;
        drawnow;
    end

    function checkLiveCancel()
        drawnow limitrate;
        if liveCancelRequested
            error('MetasurfaceExplorer:cancelled', 'Simulation cancelled by user.');
        end
    end

    function [rec, cacheKey] = getOrComputeLiveSpectrum(p, modeLabel, theta, showProgress)
        checkLiveCancel();
        p.theta = theta;
        baseKey = makeLiveBaseKey(p);
        cacheKey = makeLiveCacheKey(baseKey, modeLabel, theta);
        if isKey(liveSpectrumCache, cacheKey)
            rec = liveSpectrumCache(cacheKey);
            rec.cache_key = cacheKey;
            if ~isfield(rec, 'plot_label')
                rec.plot_label = liveRecordLabel(p, modeLabel, theta);
            end
            liveSpectrumCache(cacheKey) = rec;
            setStatus(liveStatusLabel, sprintf( ...
                'Using cached %s spectrum at theta=%g deg.', modeLabel, theta));
            return;
        end

        if strcmp(modeLabel, 'Average TE/TM')
            recTE = getOrComputeLiveSpectrum(p, 'TE', theta, showProgress);
            recTM = getOrComputeLiveSpectrum(p, 'TM', theta, showProgress);
            if numel(recTE.wavelength) ~= numel(recTM.wavelength) || ...
                    any(abs(recTE.wavelength - recTM.wavelength) > 1e-12)
                error('TE and TM wavelength grids do not match.');
            end
            rec = struct( ...
                'base_key', baseKey, ...
                'cache_key', cacheKey, ...
                'mode', modeLabel, ...
                'theta', theta, ...
                'wavelength', recTE.wavelength, ...
                'efficiency', (recTE.efficiency + recTM.efficiency) / 2, ...
                'label', sprintf('Avg TE/TM theta=%g', theta), ...
                'plot_label', liveRecordLabel(p, modeLabel, theta));
            liveSpectrumCache(cacheKey) = rec;
            return;
        end

        if strcmp(modeLabel, 'TM')
            polVal = -1;
        else
            polVal = 1;
        end

        eff = computeLiveSpectrumParallel(p, modeLabel, theta, polVal, showProgress);

        rec = struct( ...
            'base_key', baseKey, ...
            'cache_key', cacheKey, ...
            'mode', modeLabel, ...
            'theta', theta, ...
            'wavelength', siWavelength, ...
            'efficiency', eff, ...
            'label', sprintf('%s theta=%g', modeLabel, theta), ...
            'plot_label', liveRecordLabel(p, modeLabel, theta));
        liveSpectrumCache(cacheKey) = rec;
    end

    function eff = computeLiveSpectrumParallel(p, modeLabel, theta, polVal, showProgress)
        checkLiveCancel();
        Nw = numel(siWavelength);
        eff = nan(1, Nw);

        pool = gcp('nocreate');
        if isempty(pool)
            setStatus(liveStatusLabel, 'Starting parallel pool...');
            pool = parpool;
        end
        pctRunOnAll(['addpath(''' escapePathForMatlab(appDir) ''');']);
        pctRunOnAll(['addpath(''' escapePathForMatlab(rcwaDir) ''');']);

        sp = currentSpec;
        wl_arr = siWavelength;
        np_arr = siNPillar;
        liveParallelFutures = parallel.FevalFuture.empty(0, Nw);

        for k = 1:Nw
            liveParallelFutures(k) = parfeval(pool, @liveSpectrumPointSolve, 2, ...
                sp, wl_arr(k), p.h, p.ns, np_arr(k), 1, p.nc, theta, ...
                p.pitch, p.p1, p.p2, p.hc, polVal, p.nn, k);
        end

        nDone = 0;
        try
            while nDone < Nw
                checkLiveCancel();
                [~, kDone, te] = fetchNext(liveParallelFutures);
                if isempty(kDone) || isnan(kDone)
                    checkLiveCancel();
                    continue;
                end
                eff(kDone) = te;
                nDone = nDone + 1;

                if showProgress && (mod(nDone, 3) == 0 || nDone == Nw)
                    updateLiveParallelProgressPlot(wl_arr, eff, modeLabel, theta, nDone, Nw);
                else
                    setStatus(liveStatusLabel, sprintf( ...
                        '%s theta=%g: %d / %d  (%.0f%%)', ...
                        modeLabel, theta, nDone, Nw, 100*nDone/Nw));
                end
                drawnow limitrate;
            end
        catch ME
            if liveCancelRequested
                cancel(liveParallelFutures);
                error('MetasurfaceExplorer:cancelled', 'Simulation cancelled by user.');
            end
            cancel(liveParallelFutures);
            rethrow(ME);
        end

        liveParallelFutures = parallel.FevalFuture.empty;
        checkLiveCancel();
    end

    function updateLiveParallelProgressPlot(wl, eff, modeLabel, theta, nDone, Nw)
        valid = isfinite(eff);
        cla(liveSpectrumAxes);
        if any(valid)
            plot(liveSpectrumAxes, wl(valid), eff(valid), '.', ...
                'MarkerSize', 12, 'Color', liveModeColor(modeLabel, 1), ...
                'DisplayName', 'Completed wavelengths');
            hold(liveSpectrumAxes, 'on');
            plot(liveSpectrumAxes, wl(valid), eff(valid), '-', ...
                'LineWidth', 1.2, 'Color', liveModeColor(modeLabel, 1), ...
                'HandleVisibility', 'off');
            hold(liveSpectrumAxes, 'off');
        end
        xlim(liveSpectrumAxes, [wl(1) wl(end)]);
        ylim(liveSpectrumAxes, [0 1]);
        xlabel(liveSpectrumAxes, 'Wavelength (\mum)');
        ylabel(liveSpectrumAxes, 'Efficiency');
        grid(liveSpectrumAxes, 'on');
        title(liveSpectrumAxes, sprintf( ...
            '%s - %s theta=%g deg parallel (%d / %d)', ...
            currentSpec.display_name, modeLabel, theta, nDone, Nw));
        setStatus(liveStatusLabel, sprintf( ...
            '%s theta=%g: %d / %d  (%.0f%%)', ...
            modeLabel, theta, nDone, Nw, 100*nDone/Nw));
    end

    function resetLiveSpectrumAxes(titleText)
        clearAxesCompletely(liveSpectrumAxes);
        title(liveSpectrumAxes, titleText);
        xlabel(liveSpectrumAxes, 'Wavelength (\mum)');
        ylabel(liveSpectrumAxes, 'Efficiency (0-1)');
        ylim(liveSpectrumAxes, [0 1]);
        grid(liveSpectrumAxes, 'on');
        box(liveSpectrumAxes, 'on');
        legend(liveSpectrumAxes, 'off');
    end

    function addLiveDisplayedSpectrum(cacheKey)
        if isempty(cacheKey) || any(strcmp(liveDisplayedSpectrumKeys, cacheKey))
            return;
        end
        liveDisplayedSpectrumKeys{end+1} = cacheKey;
    end

    function refreshLiveSpectrumPlot()
        recs = {};
        keepKeys = {};
        for ii = 1:numel(liveDisplayedSpectrumKeys)
            cacheKey = liveDisplayedSpectrumKeys{ii};
            if isKey(liveSpectrumCache, cacheKey)
                rec = liveSpectrumCache(cacheKey);
                recs{end+1} = rec; %#ok<AGROW>
                keepKeys{end+1} = cacheKey; %#ok<AGROW>
            end
        end
        liveDisplayedSpectrumKeys = keepKeys;

        clearAxesCompletely(liveSpectrumAxes);
        if isempty(recs)
            resetLiveSpectrumAxes('Transmission Spectrum - no displayed curves');
            return;
        end

        hold(liveSpectrumAxes, 'on');
        for ii = 1:numel(recs)
            rec = recs{ii};
            lbl = rec.label;
            if isfield(rec, 'plot_label') && ~isempty(rec.plot_label)
                lbl = rec.plot_label;
            end
            cacheKey = liveDisplayedSpectrumKeys{ii};
            hLine = plot(liveSpectrumAxes, rec.wavelength, rec.efficiency, ...
                'LineWidth', 2.0, ...
                'Color', liveModeColor(rec.mode, ii), ...
                'DisplayName', lbl, ...
                'PickableParts', 'all', ...
                'HitTest', 'on', ...
                'ButtonDownFcn', @liveSpectrumCurveClicked);
            hLine.UserData = cacheKey;
        end
        hold(liveSpectrumAxes, 'off');
        allWl = cellfun(@(r) r.wavelength(:), recs, 'UniformOutput', false);
        allWl = vertcat(allWl{:});
        xlim(liveSpectrumAxes, [min(allWl) max(allWl)]);
        ylim(liveSpectrumAxes, [0 1]);
        xlabel(liveSpectrumAxes, 'Wavelength (\mum)');
        ylabel(liveSpectrumAxes, 'Efficiency');
        grid(liveSpectrumAxes, 'on');
        legend(liveSpectrumAxes, 'Location', 'best');
        title(liveSpectrumAxes, 'Live spectrum overlay - click a curve to remove it');
    end

    function liveSpectrumCurveClicked(src, ~)
        cacheKey = src.UserData;
        liveDisplayedSpectrumKeys(strcmp(liveDisplayedSpectrumKeys, cacheKey)) = [];
        refreshLiveSpectrumPlot();
        setStatus(liveStatusLabel, 'Removed selected spectrum curve from graph.');
    end

    function key = makeLiveBaseKey(p)
        key = sprintf(['shape=%s|si=%s|wl=%.12g,%.12g,%d|' ...
            'pitch=%.12g|h=%.12g|hc=%.12g|ns=%.12g|nc=%.12g|' ...
            'p1=%.12g|p2=%.12g|tMid=%.12g|tBot=%.12g|tSlices=%d|nn=%s'], ...
            currentSpec.shape_name, siFilePath, siWavelength(1), ...
            siWavelength(end), numel(siWavelength), p.pitch, p.h, p.hc, ...
            p.ns, p.nc, p.p1, p.p2, ...
            liveTaperMidField.Value, liveTaperBottomField.Value, ...
            round(liveTaperSlicesField.Value), mat2str(p.nn));
    end

    function key = makeLiveCacheKey(baseKey, modeLabel, theta)
        key = sprintf('%s|mode=%s|theta=%.12g', baseKey, modeLabel, theta);
    end

    function modeLabel = liveSpectrumModeLabel()
        val = livePolDropdown.Value;
        if contains(val, 'Average')
            modeLabel = 'Average TE/TM';
        elseif contains(val, 'TM')
            modeLabel = 'TM';
        else
            modeLabel = 'TE';
        end
    end

    function label = liveRecordLabel(p, modeLabel, theta)
        shapeName = currentSpec.shape_name;
        if isfield(currentSpec, 'display_name') && ~isempty(currentSpec.display_name)
            shapeName = currentSpec.display_name;
        end
        if currentSpec.n_geom_params == 2
            label = sprintf('%s | %s | theta=%g | pitch=%.3f, p1=%.3f, p2=%.3f', ...
                shapeName, modeLabel, theta, p.pitch, p.p1, p.p2);
        else
            label = sprintf('%s | %s | theta=%g | pitch=%.3f, p1=%.3f', ...
                shapeName, modeLabel, theta, p.pitch, p.p1);
        end
    end

    function color = liveModeColor(modeLabel, idx)
        palette = [ ...
            0.18 0.38 0.72; ...
            0.72 0.28 0.20; ...
            0.22 0.56 0.34; ...
            0.50 0.34 0.64; ...
            0.15 0.55 0.65];
        if strcmp(modeLabel, 'TM')
            palette = circshift(palette, -1, 1);
        elseif strcmp(modeLabel, 'Average TE/TM')
            palette = circshift(palette, -2, 1);
        end
        color = palette(mod(idx - 1, size(palette, 1)) + 1, :);
    end

    % -------------------------------------------------------------------
    function updateLiveFieldAxes()
        if isempty(liveField), return; end
        renderFieldAxes(liveFieldAxes, liveField, ...
            liveComponentDropdown.Value, currentSpec.display_name);
    end

    function updateLiveModelAxes()
        if isempty(currentSpec), return; end
        currentSpec = applyLiveTaperOptions(currentSpec);
        renderUnitCellAxes(liveModelAxes, currentSpec, ...
            livePitchField.Value, liveHeightField.Value, ...
            liveHCapField.Value, liveP1Field.Value, liveP2Field.Value);
    end

    function p = gatherLiveParams()
        currentSpec = applyLiveTaperOptions(currentSpec);
        wl_idx = clampIdx(liveWavelengthSlider.Value, numel(siWavelength));
        p.wl   = siWavelength(wl_idx);
        p.np   = siNPillar(wl_idx);
        p.h    = liveHeightField.Value;
        p.ns   = liveNSubField.Value;
        p.nc   = liveNCapField.Value;
        p.hc   = liveHCapField.Value;
        p.pitch = livePitchField.Value;
        p.theta = liveThetaField.Value;
        p.p1    = liveP1Field.Value;
        p.p2    = liveP2Field.Value;
        p.pol   = parsePol(livePolDropdown.Value);
        p.nn    = parseNN(liveNNField.Value);
    end

    function spec = applyLiveTaperOptions(spec)
        if isempty(spec) || ~isTaperedShape(spec)
            return;
        end
        spec.build_options.taper_mid_delta = liveTaperMidField.Value;
        spec.build_options.taper_bottom_delta = liveTaperBottomField.Value;
        spec.build_options.taper_num_slices = max(2, round(liveTaperSlicesField.Value));
    end

    function spec = applyInfoTaperOptions(spec, info)
        if isempty(spec) || ~isTaperedShape(spec)
            return;
        end
        if isfield(info, 'taper_mid_delta') && ~isnan(info.taper_mid_delta)
            spec.build_options.taper_mid_delta = info.taper_mid_delta;
        end
        if isfield(info, 'taper_bottom_delta') && ~isnan(info.taper_bottom_delta)
            spec.build_options.taper_bottom_delta = info.taper_bottom_delta;
        end
        if isfield(info, 'taper_num_slices') && ~isnan(info.taper_num_slices)
            spec.build_options.taper_num_slices = max(2, round(info.taper_num_slices));
        end
    end

    function tf = isTaperedShape(spec)
        tf = ~isempty(spec) && isfield(spec, 'shape_name') && ...
            any(strcmpi(spec.shape_name, { ...
                'tapered_cross_with_cap', ...
                'tapered_circle_with_cap'}));
    end

%% ======================================================================
%% VIEWER TAB CALLBACKS
%% ======================================================================
    function viewerBrowseFolder(~, ~)
        startFolder = viewerFolder;
        if isempty(startFolder)
            startFolder = fullfile(projectDir, 'Library Data2');
        end
        if ~exist(startFolder, 'dir')
            startFolder = pwd;
        end
        folder = uigetdir(startFolder, ...
            'Select library run folder (or a TE/TM subfolder)');
        if isequal(folder, 0), return; end

        viewerFolder = folder;
        viewerFolderLabel.Text = shortenPath(folder, 50);
        setStatus(viewerStatusLabel, 'Scanning folder...');
        drawnow;

        viewerEntries = scanViewerLibrary(folder);

        if isempty(viewerEntries)
            setStatus(viewerStatusLabel, ...
                'No theta*.mat files found. Select a run folder or a TE/TM subfolder.');
            viewerFileList.Items = {};
            viewerFiles = struct([]);
            viewerDataset = [];
            return;
        end

        viewerFiles = viewerEntries;
        relNames    = {viewerEntries.display_name};

        viewerFileList.Items = relNames;
        viewerFileList.Value = relNames{1};
        setStatus(viewerStatusLabel, ...
            sprintf('%d filter families found. Click one to load TE/TM/angle data.', ...
            numel(viewerEntries)));

        viewerFileSelected([], []);
    end

    % -------------------------------------------------------------------
    function viewerFileSelected(~, ~)
        if isempty(viewerEntries), return; end
        idx = find(strcmp(viewerFileList.Items, viewerFileList.Value), 1);
        if isempty(idx), return; end

        setStatus(viewerStatusLabel, 'Loading filter family...');
        drawnow;

        viewerDataset = loadViewerDataset(viewerEntries(idx));
        if isempty(viewerDataset.records)
            setStatus(viewerStatusLabel, 'No valid .mat files in selected family.');
            return;
        end

        info = viewerDataset.records(1).info;
        viewerInfo = info;

        try
            viewerSpec = shape_registry(info.shape_name);
            viewerSpec = applyInfoTaperOptions(viewerSpec, info);
        catch
            viewerSpec = [];
        end

        viewerInfoLabel.Text = buildFileInfoText(info);
        updateViewerDataControls();

        % P1 slider
        Np1 = numel(info.p1_values);
        viewerP1Slider.Limits = [1 max(2, Np1)];
        viewerP1Slider.Value  = 1;
        viewerP1Label.Text    = [info.p1_name '  idx:'];
        updateViewerP1Label(1);

        % P2 slider
        if info.n_geom_params == 2 && ~isempty(info.p2_values)
            Np2 = numel(info.p2_values);
            viewerP2Slider.Limits      = [1 max(2, Np2)];
            viewerP2Slider.Value       = 1;
            viewerP2Label.Text         = [info.p2_name '  idx:'];
            viewerP2Label.Visible      = 'on';
            viewerP2Slider.Visible     = 'on';
            viewerP2ValueLabel.Visible = 'on';
            updateViewerP2Label(1);
        else
            viewerP2Label.Visible      = 'off';
            viewerP2Slider.Visible     = 'off';
            viewerP2ValueLabel.Visible = 'off';
        end

        % Wavelength slider for field computation
        Nw = numel(info.wavelength);
        viewerWavelengthSlider.Limits = [1 max(2, Nw)];
        viewerWavelengthSlider.Value  = round(Nw / 2);
        updateViewerWavelengthLabel(round(Nw / 2));

        updateViewerSpectra();
        updateViewerModelAxes();
        setStatus(viewerStatusLabel, sprintf( ...
            'Loaded: %d filter(s), %d wavelengths, %d angle(s)', ...
            numel(info.p1_values) * max(1, numel(info.p2_values)), ...
            Nw, numel(viewerDataset.thetas)));
    end

    % -------------------------------------------------------------------
    function viewerP1Changed(~, event)
        updateViewerP1Label(event.Value); updateViewerSpectra(); updateViewerModelAxes();
    end
    function viewerP1Changing(~, event)
        updateViewerP1Label(event.Value); updateViewerSpectra(); updateViewerModelAxes();
    end
    function viewerP2Changed(~, event)
        updateViewerP2Label(event.Value); updateViewerSpectra(); updateViewerModelAxes();
    end
    function viewerP2Changing(~, event)
        updateViewerP2Label(event.Value); updateViewerSpectra(); updateViewerModelAxes();
    end
    function viewerShowModeChanged(~, ~)
        updateViewerSpectra();
    end
    function viewerDataModeChanged(~, ~)
        updateViewerSpectra();
    end
    function viewerAngleChanged(~, ~)
        updateViewerSpectra();
    end
    function viewerExportSpectrumExcel(~, ~)
        exportSpectrumAxesToExcel(viewerSpectrumAxes, viewerStatusLabel, ...
            'viewer_spectrum_export.xlsx');
    end
    function viewerWavelengthChanged(~, event)
        updateViewerWavelengthLabel(event.Value);
    end
    function viewerWavelengthChanging(~, event)
        updateViewerWavelengthLabel(event.Value);
    end
    function viewerComponentChanged(~, ~)
        if ~isempty(viewerField), updateViewerFieldAxes(); end
    end

    % -------------------------------------------------------------------
    function viewerComputeField(~, ~)
        if isempty(viewerInfo) || ~viewerInfo.ok
            setStatus(viewerStatusLabel, 'No file loaded.'); return; end
        if isempty(viewerSpec)
            setStatus(viewerStatusLabel, ['Unknown shape: ' viewerInfo.shape_name]);
            return;
        end

        fieldInfo = getViewerInfoForPol(parsePolLabel(viewerPolDropdown.Value), ...
            selectedViewerTheta());
        if isempty(fieldInfo)
            setStatus(viewerStatusLabel, ...
                'No .mat file is available for that field polarization/angle.'); return;
        end

        j1     = clampIdx(viewerP1Slider.Value, numel(fieldInfo.p1_values));
        p1_val = fieldInfo.p1_values(j1);

        if fieldInfo.n_geom_params == 2 && ~isempty(fieldInfo.p2_values)
            j2     = clampIdx(viewerP2Slider.Value, numel(fieldInfo.p2_values));
            p2_val = fieldInfo.p2_values(j2);
        else
            p2_val = 1;
        end

        wl_idx = clampIdx(viewerWavelengthSlider.Value, numel(fieldInfo.wavelength));
        wl     = fieldInfo.wavelength(wl_idx);

        np_arr = fieldInfo.n_pillar;
        if numel(np_arr) > 1
            np = interp1(fieldInfo.wavelength, np_arr(:), wl, 'pchip');
        else
            np = np_arr;
        end

        % Pitch: prefer stored constant, fall back to folder-name parse
        pitch = fieldInfo.pitch;
        if isnan(pitch)
            pitch = parsePitchFromPath(fieldInfo.path);
        end
        if isnan(pitch)
            setStatus(viewerStatusLabel, ...
                'Cannot determine pitch (not in file or folder name).'); return;
        end

        pol   = parsePol(viewerPolDropdown.Value);
        nn_   = parseNN(viewerNNField.Value);
        h     = fieldInfo.height;
        ns    = fieldInfo.n_substrate;
        nc    = fieldInfo.n_cap;
        hc    = fieldInfo.h_cap;
        nb    = fieldInfo.n_background;
        if isnan(nb), nb = 1; end
        theta = fieldInfo.theta;
        if isnan(theta), theta = 0; end

        setStatus(viewerStatusLabel, ...
            sprintf('Computing field at %.4f \xB5m ...', wl));
        drawnow;
        viewerComputeFieldBtn.Enable = 'off';

        try
            fieldSpec = applyInfoTaperOptions(viewerSpec, fieldInfo);
            viewerField = compute_field(fieldSpec, wl, h, ns, np, nb, nc, ...
                theta, pitch, p1_val, p2_val, hc, pol, nn_);
            updateViewerFieldAxes();
            setStatus(viewerStatusLabel, ...
                sprintf('Field ready (\x03BB = %.4f \xB5m).', wl));
        catch ME
            setStatus(viewerStatusLabel, ['Compute error: ' ME.message]);
        end
        viewerComputeFieldBtn.Enable = 'on';
    end

    % -------------------------------------------------------------------
    function updateViewerSpectra()
        if isempty(viewerInfo) || ~viewerInfo.ok, return; end
        info   = viewerInfo;
        mode   = viewerShowDropdown.Value;
        j1_sel = clampIdx(viewerP1Slider.Value, numel(info.p1_values));
        Np2    = max(1, numel(info.p2_values));
        j2_sel = clampIdx(viewerP2Slider.Value, Np2);
        dataMode = viewerDataDropdown.Value;
        thetaSel = selectedViewerTheta();

        cla(viewerSpectrumAxes);
        hold(viewerSpectrumAxes, 'on');

        if strcmp(mode, 'Selected Angle Only')
            plotThetas = thetaSel;
        else
            plotThetas = viewerDataset.thetas;
        end

        plotted = gobjects(0);
        labels  = {};
        for ti = 1:numel(plotThetas)
            theta = plotThetas(ti);
            [wl, eff, label] = spectrumForMode(dataMode, theta, j1_sel, j2_sel);
            if isempty(wl), continue; end
            c = colorForTheta(ti, numel(plotThetas));
            plotted(end+1) = plot(viewerSpectrumAxes, wl, eff, ...
                'Color', c, 'LineWidth', 2.0); %#ok<AGROW>
            labels{end+1} = label; %#ok<AGROW>
        end

        p1v     = info.p1_values(j1_sel);
        if info.n_geom_params == 2 && ~isempty(info.p2_values)
            p2v = info.p2_values(j2_sel);
            lbl = sprintf('%s=%.3f, %s=%.2f', info.p1_name, p1v, info.p2_name, p2v);
        else
            lbl = sprintf('%s=%.3f', info.p1_name, p1v);
        end
        if ~isempty(plotted)
            legend(viewerSpectrumAxes, plotted, labels, 'Location', 'best');
        end

        xlim(viewerSpectrumAxes, [info.wavelength(1) info.wavelength(end)]);
        ylim(viewerSpectrumAxes, [0 1]);
        xlabel(viewerSpectrumAxes, 'Wavelength (\mum)');
        ylabel(viewerSpectrumAxes, 'Efficiency');
        grid(viewerSpectrumAxes, 'on');
        titleStr = sprintf('%s  %s  %s', info.shape_name, dataMode, lbl);
        if strcmp(mode, 'Selected Angle Only')
            titleStr = sprintf('%s  theta=%g deg', titleStr, thetaSel);
        end
        title(viewerSpectrumAxes, titleStr);
        hold(viewerSpectrumAxes, 'off');
    end

    % -------------------------------------------------------------------
    function updateViewerFieldAxes()
        if isempty(viewerField), return; end
        shapeName = '';
        if ~isempty(viewerSpec), shapeName = viewerSpec.display_name; end
        renderFieldAxes(viewerFieldAxes, viewerField, ...
            viewerComponentDropdown.Value, shapeName);
    end

    function updateViewerModelAxes()
        if isempty(viewerInfo) || ~viewerInfo.ok || isempty(viewerSpec), return; end
        j1 = clampIdx(viewerP1Slider.Value, numel(viewerInfo.p1_values));
        p1 = viewerInfo.p1_values(j1);
        if viewerInfo.n_geom_params == 2 && ~isempty(viewerInfo.p2_values)
            j2 = clampIdx(viewerP2Slider.Value, numel(viewerInfo.p2_values));
            p2 = viewerInfo.p2_values(j2);
        else
            p2 = 1;
        end
        pitch = viewerInfo.pitch;
        if isnan(pitch)
            infoForPitch = getViewerInfoForPol('TE', selectedViewerTheta());
            if isempty(infoForPitch)
                infoForPitch = getViewerInfoForPol('TM', selectedViewerTheta());
            end
            if ~isempty(infoForPitch)
                pitch = parsePitchFromPath(infoForPitch.path);
            end
        end
        modelSpec = applyInfoTaperOptions(viewerSpec, viewerInfo);
        renderUnitCellAxes(viewerModelAxes, modelSpec, pitch, ...
            viewerInfo.height, viewerInfo.h_cap, p1, p2);
    end

    function updateViewerP1Label(val)
        if isempty(viewerInfo) || ~viewerInfo.ok, return; end
        j = clampIdx(val, numel(viewerInfo.p1_values));
        viewerP1ValueLabel.Text = sprintf('%.4f \xB5m  (idx %d / %d)', ...
            viewerInfo.p1_values(j), j, numel(viewerInfo.p1_values));
    end

    function updateViewerP2Label(val)
        if isempty(viewerInfo) || ~viewerInfo.ok || ...
           isempty(viewerInfo.p2_values), return; end
        j = clampIdx(val, numel(viewerInfo.p2_values));
        viewerP2ValueLabel.Text = sprintf('%.4f  (idx %d / %d)', ...
            viewerInfo.p2_values(j), j, numel(viewerInfo.p2_values));
    end

    function updateViewerWavelengthLabel(val)
        if isempty(viewerInfo) || ~viewerInfo.ok, return; end
        idx = clampIdx(val, numel(viewerInfo.wavelength));
        viewerWavelengthValueLabel.Text = sprintf('%.4f \xB5m  (idx %d / %d)', ...
            viewerInfo.wavelength(idx), idx, numel(viewerInfo.wavelength));
    end

    function entries = scanViewerLibrary(folder)
        entries = struct([]);
        [polDirs, polLabels] = viewerPolFolders(folder);
        records = struct([]);

        for pi = 1:numel(polDirs)
            polDir = polDirs{pi};
            hFolders = dir(fullfile(polDir, 'Height_*'));
            for hi = 1:numel(hFolders)
                if ~hFolders(hi).isdir, continue; end
                pFolders = dir(fullfile(polDir, hFolders(hi).name, 'Pitch_*'));
                for pj = 1:numel(pFolders)
                    if ~pFolders(pj).isdir, continue; end
                    familyKey = fullfile(hFolders(hi).name, pFolders(pj).name);
                    mats = dir(fullfile(polDir, familyKey, '*theta*.mat'));
                    for mi = 1:numel(mats)
                        rec.family_key = familyKey;
                        rec.display_name = strrep(familyKey, filesep, ' / ');
                        rec.pol = polLabels{pi};
                        rec.path = fullfile(mats(mi).folder, mats(mi).name);
                        rec.theta = parseThetaFromName(mats(mi).name);
                        records = [records; rec]; %#ok<AGROW>
                    end
                end
            end
        end

        if isempty(records), return; end
        keys = unique({records.family_key}, 'stable');
        for ki = 1:numel(keys)
            keep = strcmp({records.family_key}, keys{ki});
            recs = records(keep);
            pols = strjoin(unique({recs.pol}, 'stable'), '/');
            thetas = sort(unique([recs.theta]));
            if all(isnan(thetas))
                thetaText = 'theta?';
            else
                thetaVals = cellstr(compose('%g', thetas(~isnan(thetas))));
                thetaText = sprintf('theta %s', strjoin(thetaVals, ','));
            end
            entries(ki).family_key = keys{ki}; %#ok<AGROW>
            entries(ki).display_name = sprintf('%s  [%s, %s]', ...
                recs(1).display_name, pols, thetaText); %#ok<AGROW>
            entries(ki).records = recs; %#ok<AGROW>
        end
    end

    function [polDirs, polLabels] = viewerPolFolders(folder)
        [~, leaf] = fileparts(folder);
        if strcmpi(leaf, 'TE') || strcmpi(leaf, 'TM')
            polDirs = {folder};
            polLabels = {upper(leaf)};
            return;
        end

        polDirs = {};
        polLabels = {};
        for pol = {'TE', 'TM'}
            candidate = fullfile(folder, pol{1});
            if isfolder(candidate)
                polDirs{end+1} = candidate; %#ok<AGROW>
                polLabels{end+1} = pol{1}; %#ok<AGROW>
            end
        end
    end

    function dataset = loadViewerDataset(entry)
        dataset = struct('records', [], 'thetas', [], 'pols', {{}});
        records = struct([]);
        for ri = 1:numel(entry.records)
            info = read_matfile(entry.records(ri).path);
            if ~info.ok
                warning('MetasurfaceExplorer:badViewerFile', ...
                    'Skipping %s: %s', entry.records(ri).path, info.msg);
                continue;
            end
            if isempty(info.pol)
                info.pol = entry.records(ri).pol;
            end
            info.path = entry.records(ri).path;
            rec = entry.records(ri);
            rec.info = info;
            rec.theta = info.theta;
            records = [records; rec]; %#ok<AGROW>
        end
        if isempty(records), return; end
        dataset.records = records;
        dataset.thetas = sort(unique([records.theta]));
        dataset.pols = unique({records.pol}, 'stable');
    end

    function updateViewerDataControls()
        if isempty(viewerDataset) || isempty(viewerDataset.records), return; end

        oldData = '';
        if ~isempty(viewerDataDropdown.Value), oldData = viewerDataDropdown.Value; end
        oldTheta = [];
        if ~isempty(viewerAngleDropdown.Value), oldTheta = viewerAngleDropdown.Value; end

        pols = viewerDataset.pols;
        hasTE = any(strcmpi(pols, 'TE'));
        hasTM = any(strcmpi(pols, 'TM'));
        items = {};
        if hasTE, items{end+1} = 'TE'; end %#ok<AGROW>
        if hasTM, items{end+1} = 'TM'; end %#ok<AGROW>
        if hasTE && hasTM, items{end+1} = 'Average TE/TM'; end %#ok<AGROW>
        viewerDataDropdown.Items = items;
        if any(strcmp(items, oldData))
            viewerDataDropdown.Value = oldData;
        else
            viewerDataDropdown.Value = items{1};
        end

        thetas = viewerDataset.thetas;
        thetaItems = cellstr(compose('theta = %g deg', thetas));
        viewerAngleDropdown.Items = thetaItems;
        viewerAngleDropdown.ItemsData = num2cell(thetas);
        if ~isempty(oldTheta) && any(abs(thetas - oldTheta) < 1e-9)
            viewerAngleDropdown.Value = oldTheta;
        else
            viewerAngleDropdown.Value = thetas(1);
        end
    end

    function theta = selectedViewerTheta()
        theta = 0;
        if ~isempty(viewerAngleDropdown) && ~isempty(viewerAngleDropdown.Value)
            theta = viewerAngleDropdown.Value;
        elseif ~isempty(viewerInfo) && isfield(viewerInfo, 'theta')
            theta = viewerInfo.theta;
        end
    end

    function info = getViewerInfoForPol(pol, theta)
        info = [];
        if isempty(viewerDataset) || isempty(viewerDataset.records), return; end
        for ri = 1:numel(viewerDataset.records)
            rec = viewerDataset.records(ri);
            if strcmpi(rec.pol, pol) && abs(rec.theta - theta) < 1e-9
                info = rec.info;
                return;
            end
        end
    end

    function [wl, eff, label] = spectrumForMode(dataMode, theta, j1, j2)
        wl = [];
        eff = [];
        label = '';

        switch dataMode
            case 'TE'
                info = getViewerInfoForPol('TE', theta);
                if isempty(info), return; end
                wl = info.wavelength;
                eff = squeeze(info.trans_eff(:, j1, j2));
                label = sprintf('TE theta=%g', theta);
            case 'TM'
                info = getViewerInfoForPol('TM', theta);
                if isempty(info), return; end
                wl = info.wavelength;
                eff = squeeze(info.trans_eff(:, j1, j2));
                label = sprintf('TM theta=%g', theta);
            otherwise
                teInfo = getViewerInfoForPol('TE', theta);
                tmInfo = getViewerInfoForPol('TM', theta);
                if isempty(teInfo) || isempty(tmInfo), return; end
                wl = teInfo.wavelength;
                eff = (squeeze(teInfo.trans_eff(:, j1, j2)) + ...
                    squeeze(tmInfo.trans_eff(:, j1, j2))) / 2;
                label = sprintf('Avg theta=%g', theta);
        end
    end

    function c = colorForTheta(idx, n)
        if n <= 1
            c = [0.88 0.25 0.18];
            return;
        end
        cmap = lines(max(n, 3));
        c = cmap(idx, :);
    end

%% ======================================================================
%% SHARED RENDERING
%% ======================================================================
    function renderUnitCellAxes(ax, spec, period, height, h_cap, p1, p2)
        if isempty(ax) || isempty(spec), return; end
        if isempty(period) || isnan(period) || period <= 0, period = max(p1 * 1.5, 1); end
        if isempty(height) || isnan(height) || height <= 0, height = 1; end
        if isempty(h_cap) || isnan(h_cap) || h_cap < 0, h_cap = 0; end
        if isempty(p1) || isnan(p1) || p1 <= 0, p1 = period * 0.4; end
        if isempty(p2) || isnan(p2) || p2 <= 0, p2 = 1; end

        cla(ax);
        hold(ax, 'on');

        subT = max(0.12 * height, 0.06);
        drawBox(ax, period, period, subT, [0 0 -subT], [0.72 0.76 0.82], 0.45);

        pillarColor = [0.42 0.55 0.95];
        capColor    = [0.95 0.76 0.35];
        if strcmpi(spec.shape_name, 'tapered_cross_with_cap')
            drawTaperedCrossPillar(ax, spec, p1, p2, height, 0, pillarColor, 0.92);
        elseif strcmpi(spec.shape_name, 'tapered_circle_with_cap')
            drawTaperedCirclePillar(ax, spec, p1, height, 0, pillarColor, 0.92);
        else
            drawShapeLayer(ax, spec.shape_name, p1, p2, height, 0, pillarColor, 0.92);
        end
        if h_cap > 0
            drawShapeLayer(ax, spec.shape_name, p1, p2, h_cap, height, capColor, 0.95);
        end

        hold(ax, 'off');
        axis(ax, 'equal');
        grid(ax, 'on');
        box(ax, 'on');
        xlabel(ax, 'x (\mum)');
        ylabel(ax, 'y (\mum)');
        zlabel(ax, 'z (\mum)');
        view(ax, 35, 24);
        xlim(ax, [-period/2 period/2]);
        ylim(ax, [-period/2 period/2]);
        zlim(ax, [-subT height + max(h_cap, eps)]);
        title(ax, unitCellTitle(spec, period, height, h_cap));
        camlight(ax, 'headlight');
        lighting(ax, 'gouraud');
    end

    function txt = unitCellTitle(spec, period, height, h_cap)
        txt = sprintf('%s | P=%.3g, H=%.3g, cap=%.3g um', ...
            spec.display_name, period, height, h_cap);
        if isTaperedShape(spec)
            opts = taperOptionsFromSpec(spec);
            txt = sprintf('%s | mid %+.3g, bot %+.3g, %d slices', ...
                txt, opts.taper_mid_delta, opts.taper_bottom_delta, ...
                opts.taper_num_slices);
        end
    end

    function drawShapeLayer(ax, shapeName, p1, p2, layerHeight, z0, color, alpha)
        switch lower(shapeName)
            case {'cross_with_cap', 'tapered_cross_with_cap'}
                w1 = p1;
                w2 = p1 * p2;
                drawBox(ax, w1, w2, layerHeight, [0 0 z0], color, alpha);
                drawBox(ax, w2, w1, layerHeight, [0 0 z0], color, alpha);
            case 'square_with_cap'
                drawBox(ax, p1, p1, layerHeight, [0 0 z0], color, alpha);
            case {'circle_with_cap', 'tapered_circle_with_cap'}
                drawEllipticCylinder(ax, p1, p1, layerHeight, z0, color, alpha);
            case 'ellipse_with_cap'
                drawEllipticCylinder(ax, p1, p1 * p2, layerHeight, z0, color, alpha);
            otherwise
                drawBox(ax, p1, p1, layerHeight, [0 0 z0], color, alpha);
        end
    end

    function drawTaperedCrossPillar(ax, spec, p1, p2, height, z0, color, alpha)
        opts = taperOptionsFromSpec(spec);
        widths = taperedWidthsForDisplay(p1, ...
            p1 + opts.taper_mid_delta, ...
            p1 + opts.taper_bottom_delta, ...
            opts.taper_num_slices);
        sliceH = height / numel(widths);
        for ii = 1:numel(widths)
            w1 = widths(ii);
            if w1 <= 0, continue; end
            w2 = w1 * p2;
            zBase = z0 + height - ii * sliceH;
            drawBox(ax, w1, w2, sliceH, [0 0 zBase], color, alpha);
            drawBox(ax, w2, w1, sliceH, [0 0 zBase], color, alpha);
        end
    end

    function drawTaperedCirclePillar(ax, spec, p1, height, z0, color, alpha)
        opts = taperOptionsFromSpec(spec);
        diameters = taperedWidthsForDisplay(p1, ...
            p1 + opts.taper_mid_delta, ...
            p1 + opts.taper_bottom_delta, ...
            opts.taper_num_slices);
        sliceH = height / numel(diameters);
        for ii = 1:numel(diameters)
            d = diameters(ii);
            if d <= 0, continue; end
            zBase = z0 + height - ii * sliceH;
            drawEllipticCylinder(ax, d, d, sliceH, zBase, color, alpha);
        end
    end

    function opts = taperOptionsFromSpec(spec)
        opts = struct('taper_mid_delta', 0, ...
            'taper_bottom_delta', 0, ...
            'taper_num_slices', 6);
        if isfield(spec, 'build_options') && ~isempty(spec.build_options)
            names = fieldnames(opts);
            for ii = 1:numel(names)
                if isfield(spec.build_options, names{ii}) && ...
                        ~isempty(spec.build_options.(names{ii}))
                    opts.(names{ii}) = spec.build_options.(names{ii});
                end
            end
        end
        opts.taper_num_slices = max(2, round(opts.taper_num_slices));
    end

    function widths = taperedWidthsForDisplay(topW, midW, bottomW, nSlices)
        if nSlices == 2
            widths = [topW, bottomW];
            return;
        end
        z = linspace(0, 1, nSlices);
        widths = zeros(1, nSlices);
        for ii = 1:nSlices
            if z(ii) <= 0.5
                a = z(ii) / 0.5;
                widths(ii) = (1 - a) * topW + a * midW;
            else
                a = (z(ii) - 0.5) / 0.5;
                widths(ii) = (1 - a) * midW + a * bottomW;
            end
        end
    end

    function drawBox(ax, Lx, Ly, Lz, origin, faceColor, alpha)
        x0 = origin(1); y0 = origin(2); z0 = origin(3);
        xv = [-Lx/2 Lx/2] + x0;
        yv = [-Ly/2 Ly/2] + y0;
        zv = [0 Lz] + z0;
        V = [xv(1) yv(1) zv(1); xv(2) yv(1) zv(1); ...
             xv(2) yv(2) zv(1); xv(1) yv(2) zv(1); ...
             xv(1) yv(1) zv(2); xv(2) yv(1) zv(2); ...
             xv(2) yv(2) zv(2); xv(1) yv(2) zv(2)];
        Fc = [1 2 3 4; 5 6 7 8; 1 2 6 5; ...
              2 3 7 6; 3 4 8 7; 4 1 5 8];
        patch(ax, 'Vertices', V, 'Faces', Fc, 'FaceColor', faceColor, ...
            'FaceAlpha', alpha, 'EdgeColor', [0.18 0.18 0.18], ...
            'LineWidth', 0.5);
    end

    function drawEllipticCylinder(ax, diamX, diamY, height, z0, faceColor, alpha)
        n = 72;
        t = linspace(0, 2*pi, n);
        x = (diamX / 2) * cos(t);
        y = (diamY / 2) * sin(t);
        zBottom = z0 * ones(size(t));
        zTop = (z0 + height) * ones(size(t));
        surf(ax, [x; x], [y; y], [zBottom; zTop], ...
            'FaceColor', faceColor, 'FaceAlpha', alpha, ...
            'EdgeColor', 'none');
        patch(ax, x, y, zBottom, faceColor, 'FaceAlpha', alpha, ...
            'EdgeColor', [0.18 0.18 0.18], 'LineWidth', 0.4);
        patch(ax, x, y, zTop, faceColor, 'FaceAlpha', alpha, ...
            'EdgeColor', [0.18 0.18 0.18], 'LineWidth', 0.4);
    end

    function renderFieldAxes(ax, F, comp, shapeName)
        data = extractComponent(F, comp);
        cla(ax);
        [X, Z] = meshgrid(F.x, F.z);
        surface(ax, X, Z, zeros(size(data)), data, ...
            'EdgeColor', 'none', 'FaceColor', 'interp');
        view(ax, 2);
        axis(ax, 'xy');
        xlim(ax, [min(F.x) max(F.x)]);
        ylim(ax, [min(F.z) max(F.z)]);
        colorbar(ax);
        colormap(ax, fieldColormap(comp));
        xlabel(ax, 'x (\mum)');
        ylabel(ax, 'z (\mum)');
        title(ax, sprintf('%s \x2014 %s,  \x03BB = %.4f \xB5m', ...
            comp, shapeName, F.wavelength));
        hold(ax, 'on');
        % Layer boundaries
        yline(ax, F.z_sub_top, '--', 'Color', [1 1 1 0.75], 'LineWidth', 1);
        yline(ax, F.z_pil_top, '--', 'Color', [1 1 1 0.75], 'LineWidth', 1);
        yline(ax, F.z_cap_top, '--', 'Color', [1 1 1 0.75], 'LineWidth', 1);
        % Pillar x-extent
        xline(ax,  F.pillar_xwidth/2, ':', 'Color', [1 1 1 0.60], 'LineWidth', 1);
        xline(ax, -F.pillar_xwidth/2, ':', 'Color', [1 1 1 0.60], 'LineWidth', 1);
        hold(ax, 'off');
    end

    function data = extractComponent(F, comp)
        switch comp
            case '|E|',   data = F.Eabs;
            case '|H|',   data = F.Habs;
            case 'Ex',    data = real(F.Ex);
            case 'Ey',    data = real(F.Ey);
            case 'Ez',    data = real(F.Ez);
            case 'Hx',    data = real(F.Hx);
            case 'Hy',    data = real(F.Hy);
            case 'Hz',    data = real(F.Hz);
            case 'Re(n)', data = real(F.index);
            case 'Im(n)', data = imag(F.index);
            otherwise,    data = F.Eabs;
        end
    end

    function cm = fieldColormap(comp)
        switch comp
            case {'|E|','|H|','Im(n)'}
                cm = 'hot';
            otherwise
                N  = 64;
                r  = [linspace(0.18, 1, N), ones(1,  N)]';
                g  = [linspace(0.38, 1, N), linspace(1, 0.15, N)]';
                b  = [ones(1, N),           linspace(1, 0.18, N)]';
                cm = [r g b];
        end
    end

%% ======================================================================
%% SMALL UTILITIES
%% ======================================================================
    function pol = parsePol(str)
        pol = 1;
        if contains(str, 'TM') || contains(str, '-1'), pol = -1; end
    end

    function pol = parsePolLabel(str)
        if contains(str, 'TM')
            pol = 'TM';
        else
            pol = 'TE';
        end
    end

    function nn_ = parseNN(str)
        parts = str2num(str); %#ok<ST2NM>
        if numel(parts) >= 2,     nn_ = parts(1:2);
        elseif numel(parts) == 1, nn_ = [parts(1) parts(1)];
        else,                     nn_ = [12 12];
        end
    end

    function j = clampIdx(val, maxVal)
        j = max(1, min(round(val), maxVal));
    end

    function setStatus(lbl, msg)
        lbl.Text = msg; drawnow;
    end

    function exportSpectrumAxesToExcel(ax, statusLabel, defaultName)
        lineObjs = findobj(ax, 'Type', 'Line');
        lineObjs = flipud(lineObjs(:));
        keep = false(size(lineObjs));
        for ii = 1:numel(lineObjs)
            x = lineObjs(ii).XData;
            y = lineObjs(ii).YData;
            keep(ii) = numel(x) >= 2 && numel(y) >= 2 && ...
                numel(x) == numel(y) && any(isfinite(x)) && any(isfinite(y));
        end
        lineObjs = lineObjs(keep);

        if isempty(lineObjs)
            setStatus(statusLabel, 'No spectrum curves to export.');
            return;
        end

        [fileName, folderName] = uiputfile( ...
            {'*.xlsx', 'Excel Workbook (*.xlsx)'}, ...
            'Export Spectrum Curves', defaultName);
        if isequal(fileName, 0)
            return;
        end

        outPath = fullfile(folderName, fileName);
        usedSheets = {};
        try
            for ii = 1:numel(lineObjs)
                x = lineObjs(ii).XData(:);
                y = lineObjs(ii).YData(:);
                good = isfinite(x) & isfinite(y);
                x = x(good);
                y = y(good);

                [x, order] = sort(x);
                y = y(order);

                label = string(lineObjs(ii).DisplayName);
                if strlength(label) == 0 || strcmp(label, "")
                    label = sprintf("Curve_%d", ii);
                end
                sheetName = uniqueSheetName(label, usedSheets, ii);
                usedSheets{end+1} = sheetName; %#ok<AGROW>

                outCell = [{'wavelength', 'intensity'}; ...
                    num2cell([x, y])];
                writecell(outCell, outPath, 'Sheet', sheetName);
            end
            setStatus(statusLabel, sprintf( ...
                'Exported %d spectrum curve(s) to %s', numel(lineObjs), outPath));
        catch ME
            setStatus(statusLabel, ['Export error: ' ME.message]);
        end
    end

    function sheetName = uniqueSheetName(label, usedSheets, idx)
        sheetName = char(label);
        sheetName = regexprep(sheetName, '[:\\/?*\[\]]', '_');
        sheetName = regexprep(sheetName, '\s+', ' ');
        sheetName = strtrim(sheetName);
        if isempty(sheetName)
            sheetName = sprintf('Curve_%d', idx);
        end
        if numel(sheetName) > 31
            sheetName = sheetName(1:31);
        end

        baseName = sheetName;
        suffix = 2;
        while any(strcmpi(usedSheets, sheetName))
            suffixText = sprintf('_%d', suffix);
            maxBase = 31 - numel(suffixText);
            sheetName = [baseName(1:min(numel(baseName), maxBase)) suffixText];
            suffix = suffix + 1;
        end
    end

    function clearAxesCompletely(ax)
        try
            legend(ax, 'off');
        catch
        end
        try
            delete(ax.Children);
        catch
        end
        try
            cla(ax, 'reset');
        catch
            cla(ax);
        end
        ax.NextPlot = 'replace';
    end

    function val = ternaryOnOff(tf)
        if tf
            val = 'on';
        else
            val = 'off';
        end
    end

    function pathOut = escapePathForMatlab(pathIn)
        pathOut = strrep(pathIn, '''', '''''');
    end

    function txt = buildFileInfoText(info)
        p2str = '';
        if info.n_geom_params == 2 && ~isempty(info.p2_values)
            p2str = sprintf(', %s: %d pts', info.p2_name, numel(info.p2_values));
        end
        taperStr = '';
        if isfield(info, 'taper_mid_delta') && ~isnan(info.taper_mid_delta)
            taperStr = sprintf('\nTaper: mid %+.3f um, bottom %+.3f um, slices %.0f', ...
                info.taper_mid_delta, info.taper_bottom_delta, info.taper_num_slices);
        end
        polStr = info.pol; if isempty(polStr), polStr = '?'; end
        txt = sprintf( ...
            'Shape: %s  |  h=%.2f\xB5m  |  \x03B8=%g\xB0  |  pol: %s\n%s: %d pts%s%s', ...
            info.shape_name, info.height, info.theta, polStr, ...
            info.p1_name, numel(info.p1_values), p2str, taperStr);
    end

    function pitch = parsePitchFromPath(folderPath)
        tok = regexp(folderPath, 'Pitch_([0-9]+[.,]?[0-9]*)', 'tokens', 'once');
        if isempty(tok), pitch = NaN;
        else, pitch = str2double(strrep(tok{1}, ',', '.')); end
    end

    function theta = parseThetaFromName(filename)
        tok = regexp(filename, 'theta(-?\d+)', 'tokens', 'once');
        if isempty(tok), theta = NaN;
        else, theta = str2double(tok{1}); end
    end

    function s = shortenPath(p, maxLen)
        if numel(p) <= maxLen, s = p;
        else, s = ['...' p(end-maxLen+4:end)]; end
    end

    function secLabel(parent, txt, x, y)
        uilabel(parent, 'Text', txt, ...
            'Position', [x y 335 20], ...
            'FontWeight', 'bold', 'FontColor', [0.18 0.45 0.72]);
    end

end % MetasurfaceExplorer
