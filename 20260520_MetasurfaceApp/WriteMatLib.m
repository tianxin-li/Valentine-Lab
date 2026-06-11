function full_filename = WriteMatLib(spec, wavelength_band, units, data_format, ...
        pitch, height, pol, timestamp, base_path, varargin)
% WRITEMATLIB  Serialise one RCWA library result to a .mat file.
%
%   Unified replacement for WriteMatCross_v2 and WriteMat3. Works for any
%   shape registered in shape_registry. The only required change when adding
%   a new shape is in shape_registry — this writer needs no modification.
%
%   full_filename = WriteMatLib(spec, wavelength_band, units, data_format, ...
%       pitch, height, pol, timestamp, base_path, varargin)
%
% -----------------------------------------------------------------------
%   FIXED ARGUMENTS
% -----------------------------------------------------------------------
%   spec           : shape spec struct from shape_registry(shape_name)
%   wavelength_band: waveband label string, e.g. 'SWIR'
%   units          : length unit string, e.g. 'um'
%   data_format    : data format label, e.g. 'AmpPhase'
%   pitch          : unit-cell pitch in micrometres (scalar)
%   height         : pillar height in micrometres (scalar)
%   pol            : polarization string, 'TE' or 'TM'
%   timestamp      : run-start timestamp string, e.g. '2026-05-16_143022'
%                    Fixed for the whole pipeline run so cross-midnight
%                    runs stay in one folder.
%   base_path      : root save directory (macOS or Windows, set by driver)
%
% -----------------------------------------------------------------------
%   KEYWORD VARARGIN (repeatable where indicated)
% -----------------------------------------------------------------------
%   'Material', mat_name, use, index, notes   % repeatable
%       mat_name : string  e.g. 'Si'
%       use      : string  'pillar' | 'substrate' | 'background' | 'cap'
%       index    : scalar or [Nw x 1] complex refractive index
%       notes    : string  any descriptive note
%
%   'Param', name, [min max n], notes         % repeatable
%       name  : string  e.g. 'wavelength', 'diameter', 'width', 'aspect_ratio'
%       value : [1x3]  [min_val, max_val, num_points]
%       notes : string
%
%   'Constant', name, value, notes            % repeatable
%       name  : string  e.g. 'height', 'theta', 'h_cap', 'n_cap'
%       value : scalar
%       notes : string
%
%   'Data', name, array, notes                % repeatable
%       name  : string  e.g. 'transmission_bottom_0_0_efficiency'
%       array : numeric array of any shape
%       notes : string
%
%   'Creator', string
%   'Notes',   string
%
% -----------------------------------------------------------------------
%   FOLDER TREE PRODUCED
% -----------------------------------------------------------------------
%   base_path /
%     <pillar>_on_<substrate>_<shape_name> /
%       <timestamp> /
%         <pol> /
%           Height_H.HH /
%             Pitch_P.PP /
%               <filename>.mat
%
%   Filename format:
%     <waveband>_<pillar>_on_<substrate>_<shape>_H<height_int>_P<pitch_int>_theta<angle>.mat
%
% -----------------------------------------------------------------------
%   RETURNS
% -----------------------------------------------------------------------
%   full_filename : full path of the .mat file that was written

    % --- folder name fragments ------------------------------------------
    pol           = char(pol);
    timestamp     = char(timestamp);
    pitch_folder  = sprintf('Pitch_%05.3f', pitch);
    height_folder = sprintf('Height_%04.2f', height);

    % --- defaults -------------------------------------------------------
    array_type               = 'square';
    dispersion_flag          = false;
    material_names           = {};
    material_use             = {};
    material_index           = {};
    material_notes           = {};
    material_dispersion_flag = logical([]);
    param_names              = {};
    param_values             = {};
    param_notes              = {};
    constant_names           = {};
    constant_values          = {};
    constant_notes           = {};
    data_names               = {};
    data_values              = {};
    data_notes               = {};
    creator                  = '';
    notes                    = '';
    theta                    = [];   % extracted from Constants for filename

    % --- parse varargin -------------------------------------------------
    i = 1;
    while i <= numel(varargin)
        switch varargin{i}

            case 'Material'
                material_names{end+1}  = char(varargin{i+1});
                material_use{end+1}    = char(varargin{i+2});
                material_index{end+1}  = varargin{i+3};
                material_notes{end+1}  = char(varargin{i+4});
                if numel(varargin{i+3}) > 1
                    material_dispersion_flag(end+1) = true;
                    dispersion_flag = true;
                else
                    material_dispersion_flag(end+1) = false;
                end
                i = i + 5;

            case 'Param'
                param_names{end+1}  = char(varargin{i+1});
                param_values{end+1} = varargin{i+2};
                param_notes{end+1}  = char(varargin{i+3});
                i = i + 4;

            case 'Constant'
                constant_names{end+1}  = char(varargin{i+1});
                constant_values{end+1} = varargin{i+2};
                constant_notes{end+1}  = char(varargin{i+3});
                if strcmpi(varargin{i+1}, 'theta')
                    theta = varargin{i+2};
                end
                i = i + 4;

            case 'Data'
                data_names{end+1}  = char(varargin{i+1});
                data_values{end+1} = varargin{i+2};
                data_notes{end+1}  = char(varargin{i+3});
                i = i + 4;

            case 'Creator'
                creator = char(varargin{i+1});
                i = i + 2;

            case 'Notes'
                notes = char(varargin{i+1});
                i = i + 2;

            otherwise
                error('WriteMatLib:badParam', ...
                    'Unrecognised keyword: "%s" (argument %d)', varargin{i}, i);
        end
    end

    % --- validate required metadata -------------------------------------
    if ~any(strcmpi(constant_names, 'height'))
        error('WriteMatLib:noHeight', ...
            'Must pass height as a Constant: ''Constant'', ''height'', value, notes');
    end
    if ~any(strcmpi(material_use, 'substrate'))
        error('WriteMatLib:noSubstrate', ...
            'Must pass substrate material: ''Material'', name, ''substrate'', index, notes');
    end
    if ~any(strcmpi(material_use, 'pillar'))
        error('WriteMatLib:noPillar', ...
            'Must pass pillar material: ''Material'', name, ''pillar'', index, notes');
    end

    % --- extract material names for folder / filename construction ------
    substrate_mat = material_names{strcmpi(material_use, 'substrate')};
    pillar_mat    = material_names{strcmpi(material_use, 'pillar')};

    % --- build filename -------------------------------------------------
    height_int = round(height * 100);
    pitch_int  = round(pitch  * 100);

    base_filename = sprintf('%s_%s_on_%s_%s_H%04d_P%04d', ...
        wavelength_band, pillar_mat, substrate_mat, spec.shape_name, ...
        height_int, pitch_int);

    if ~isempty(theta)
        filename = sprintf('%s_theta%d.mat', base_filename, theta);
    else
        filename = sprintf('%s_0.mat', base_filename);
    end

    % --- build directory tree -------------------------------------------
    material_folder = sprintf('%s_on_%s_%s', ...
        pillar_mat, substrate_mat, spec.shape_name);

    save_dir = fullfile(base_path, material_folder, timestamp, ...
        pol, height_folder, pitch_folder);

    if ~exist(save_dir, 'dir')
        mkdir(save_dir);
    end

    % --- assemble variables to save -------------------------------------
    % Store spec metadata so the file is self-describing:
    %   unit_cell_type  — matches spec.shape_name (kept for reader compatibility)
    %   shape_tag       — short human label from the spec
    %   n_geom_params   — tells the reader how many sweep params this shape has
    %   pol_saved       — which polarization this file contains
    unit_cell_type = spec.shape_name;
    shape_tag      = spec.shape_tag;
    n_geom_params  = spec.n_geom_params;
    pol_saved      = pol;
    run_timestamp  = timestamp;
    date_created   = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    % --- save -----------------------------------------------------------
    full_filename = fullfile(save_dir, filename);
    fprintf('  Saving: %s\n', full_filename);

    save(full_filename, ...
        'unit_cell_type', 'shape_tag', 'n_geom_params', ...
        'pol_saved', 'run_timestamp', 'date_created', ...
        'array_type', 'creator', 'data_format', 'wavelength_band', ...
        'units', 'dispersion_flag', 'notes', ...
        'material_names', 'material_use', 'material_index', ...
        'material_notes', 'material_dispersion_flag', ...
        'param_names', 'param_values', 'param_notes', ...
        'constant_names', 'constant_values', 'constant_notes', ...
        'data_names', 'data_values', 'data_notes');
end
