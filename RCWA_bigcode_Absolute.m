function [transmitted, reflected, trans_efficiency, refl_efficiency] = RCWA_bigcode_Absolute(wavelength, height, n_substrate, n_pillar, n_background, pillar_type, angle_of_incidence, period, varargin)
%Calculate complex amplitude of normally incident transmitted light through square array of pillars
% --- INPUTS ---
% --- All geometric inputs are normalized by wavelength ---
% wavelength       - wavelength of incident light
% height           - height of pillars
% n_background     - index of refraction of background material (air, etc.)
% n_pillar         - index of refraction of pillars
% n_substrate      - index of refraction of substrate
% pillar_type      - pillar shape (Options: 'circle', 'square',
                      %               'ellipse', 'rectangle', 'cross')
% varargin         - geometric parameters for pillar_type
                      % 'circle':    1 input: diameter
                      % 'square':    1 input: width
                      % 'ellipse':   2 inputs: x-diameter, y-diameter
                      % 'rectangle': 2 inputs: x-width, y-width
                      % 'cross':     2 inputs: width, minor_width
                      % 'anticross': 2 inputs: width, hole_minor_width
                      % 'squarering': 2 inputs: width, hole_width
                      % 'circle_coat': 3 inputs: diameter, thickness, n_coating
                      % 'circle_emb':3 inputs: diameter, thickness, n_coating
                      % 'square_hole': 1 input: width
                      % 'rectangle_hole: 2 inputs: x-width, y-width

% --- OUTPUTS ---
% amplitude        - Complex relative amplitude of 0 order transmitted TEM
                      % light for incident TEM light on bottom of substrate
                      % if pillar_type is rectangle or ellipse, amplitude
                      % will be a length 2 array of complex
                      % transmissivities: E aligned with x axis, E aligned
                      % with y axis.

%% Define Parameters and Textures


parm = res0;    %loads the default parameters
parm.not_io = 1;

parm.sym.x = 0;     %x-direction mirror symmetry plane
parm.sym.y = 0;     %y-direction mirror symmetry plane
parm.sym.pol = (1);   %polarization, TE = 1, TM = -1

retio({},inf*1i);
% parm.res1.trace = 1; %Sets option to plot textures when running res1
% parm.res1.champ = 1; %Improves calculation of EM fields (not needed if
                        % just calculating transmission/reflection)

textures = cell(1,3);
textures{1} = n_background;
switch pillar_type
    case 'circle'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
    case 'circle_on_circle'
        % varargin 1 = diameter
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
        textures{3} = {n_background, [0, 0, varargin{1}, varargin{1}, n_substrate, 36]};
        textures{4} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
    case 'circle_2'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
    case 'circle_with_cap'
        n_cap = varargin{3};
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_cap, 36]};
        textures{3} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
    case 'square_with_cap'
        n_cap = varargin{3};
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_cap, 1]};
        textures{3} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 1]};
    case 'square'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 1]};
    case 'ellipse'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{2}, n_pillar, 36]};
    case 'rectangle'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{2}, n_pillar, 1]};
    case 'cross'
        textures{2} = {n_background, [0,0,varargin{1},varargin{2},n_pillar,1],[0,0,varargin{2},varargin{1},n_pillar,1]};
    case 'cross_with_cap'
        n_cap = varargin{4};
        textures{2} = {n_background, [0,0,varargin{1},varargin{2},n_cap,1],[0,0,varargin{2},varargin{1},n_cap,1]};
        textures{3} = {n_background, [0,0,varargin{1},varargin{2},n_pillar,1],[0,0,varargin{2},varargin{1},n_pillar,1]};
    case 'elliptical_cross_with_cap'
        n_cap = varargin{4};
        % A value for the staircase approximation of the ellipse.
        % Higher numbers give a smoother ellipse. Recommended N >= 5.
        num_ellipse_segments = 20; 
             % Defines a cross using two ELLIPTICAL inclusions.
        % Note that the last parameter is now 'num_ellipse_segments' instead of 1.
        % varargin{1} is the major axis, varargin{2} is the minor axis.
        textures{2} = {n_background, [0,0,varargin{1},varargin{2},n_cap,num_ellipse_segments],[0,0,varargin{2},varargin{1},n_cap,num_ellipse_segments]};
        textures{3} = {n_background, [0,0,varargin{1},varargin{2},n_pillar,num_ellipse_segments],[0,0,varargin{2},varargin{1},n_pillar,num_ellipse_segments]};

    case 'anticross'
        textures{2} = {n_background, [0,0,varargin{1},varargin{1},n_pillar,1], [0,0,varargin{1},varargin{2},n_background,1],[0,0,varargin{2},varargin{1},n_background,1]};
    case 'Complex_Cross_1' %% Cross with Squares in the corners
        n_cap = varargin{5};
        textures{2} = {
                    n_background, ...
                    [0, 0, varargin{1}, varargin{2}, n_cap, 1], ...   % horizontal arm
                    [0, 0, varargin{2}, varargin{1}, n_cap, 1], ...   % vertical arm
                    [ varargin{1}/2,  varargin{1}/2, varargin{3}, varargin{3}, n_cap, 1], ... % top-right corner
                    [ varargin{1}/2,  -(varargin{1}/2), varargin{3}, varargin{3}, n_cap, 1], ... % top-left corner
                    [ -(varargin{1}/2),  varargin{1}/2, varargin{3}, varargin{3}, n_cap, 1], ... % bottom-right corner
                    [ -(varargin{1}/2),  -(varargin{1}/2), varargin{3}, varargin{3}, n_cap, 1]      % bottom-left corner
                };
        textures{3} = {
                    n_background, ...
                    [0, 0, varargin{1}, varargin{2}, n_pillar, 1], ...   % horizontal arm
                    [0, 0, varargin{2}, varargin{1}, n_pillar, 1], ...   % vertical arm
                    [ varargin{1}/2,  varargin{1}/2, varargin{3}, varargin{3}, n_pillar, 1], ... % top-right corner
                    [ varargin{1}/2,  -(varargin{1}/2), varargin{3}, varargin{3}, n_pillar, 1], ... % top-left corner
                    [ -(varargin{1}/2),  varargin{1}/2, varargin{3}, varargin{3}, n_pillar, 1], ... % bottom-right corner
                    [ -(varargin{1}/2),  -(varargin{1}/2), varargin{3}, varargin{3}, n_pillar, 1]      % bottom-left corner
                };
    case 'Complex_Cross_2' %% Cross with Circles in the corners
        n_cap = varargin{5};
        textures{2} = {
                    n_background, ...
                    [0, 0, varargin{1}, varargin{2}, n_cap, 1], ...   % horizontal arm
                    [0, 0, varargin{2}, varargin{1}, n_cap, 1], ...   % vertical arm
                    [ varargin{1}/2,  varargin{1}/2, varargin{3}, varargin{3}, n_cap, 36], ... % top-right corner
                    [ varargin{1}/2,  -(varargin{1}/2), varargin{3}, varargin{3}, n_cap, 36], ... % top-left corner
                    [ -(varargin{1}/2),  varargin{1}/2, varargin{3}, varargin{3}, n_cap, 36], ... % bottom-right corner
                    [ -(varargin{1}/2),  -(varargin{1}/2), varargin{3}, varargin{3}, n_cap, 36]      % bottom-left corner
                };
        textures{3} = {
                    n_background, ...
                    [0, 0, varargin{1}, varargin{2}, n_pillar, 1], ...   % horizontal arm
                    [0, 0, varargin{2}, varargin{1}, n_pillar, 1], ...   % vertical arm
                    [ varargin{1}/2,  varargin{1}/2, varargin{3}, varargin{3}, n_pillar, 36], ... % top-right corner
                    [ varargin{1}/2,  -(varargin{1}/2), varargin{3}, varargin{3}, n_pillar, 36], ... % top-left corner
                    [ -(varargin{1}/2),  varargin{1}/2, varargin{3}, varargin{3}, n_pillar, 36], ... % bottom-right corner
                    [ -(varargin{1}/2),  -(varargin{1}/2), varargin{3}, varargin{3}, n_pillar, 36]      % bottom-left corner
                };
    case 'Complex_Cross_Winston' % Symmetrical cross with corner circles
        % --- Define Geometric & Material Parameters ---
        D        = varargin{1}; % Major length of the cross arms
        w_bar    = varargin{2}; % Minor width of the cross arms
        D_disk   = varargin{3}; % Diameter of the corner disks
        n_cap    = varargin{5}; % Refractive index of the cap material
        
        % Use the 'period' variable (passed into the function) for the symmetric calculation
        C = (period + w_bar) / 4;
    
        % --- Define the shapes for the CAP layer (textures{2}) ---
        textures{2} = {
            n_background, ...
            [0, 0, D, w_bar, n_cap, 1], ...      % Horizontal arm (cap)
            [0, 0, w_bar, D, n_cap, 1], ...      % Vertical arm (cap)
            [ C,  C, D_disk, D_disk, n_cap, 36], ... % Top-right disk (cap)
            [-C,  C, D_disk, D_disk, n_cap, 36], ... % Top-left disk (cap)
            [-C, -C, D_disk, D_disk, n_cap, 36], ... % Bottom-left disk (cap)
            [ C, -C, D_disk, D_disk, n_cap, 36]     % Bottom-right disk (cap)
        };
        
        % --- [FIX] ADD THE MISSING PILLAR LAYER DEFINITION ---
        % This part was missing. It's the same geometry as the cap, but uses n_pillar.
        textures{3} = {
            n_background, ...
            [0, 0, D, w_bar, n_pillar, 1], ...   % Horizontal arm (pillar)
            [0, 0, w_bar, D, n_pillar, 1], ...   % Vertical arm (pillar)
            [ C,  C, D_disk, D_disk, n_pillar, 36], ... % Top-right disk (pillar)
            [-C,  C, D_disk, D_disk, n_pillar, 36], ... % Top-left disk (pillar)
            [-C, -C, D_disk, D_disk, n_pillar, 36], ... % Bottom-left disk (pillar)
            [ C, -C, D_disk, D_disk, n_pillar, 36]  ... % Bottom-right disk (pillar)
        };
    case 'squarering'
        textures{2} = {n_background, [0,0,varargin{1},varargin{1},n_pillar,1],[0,0,varargin{2},varargin{2},n_background,1]};
    case 'square_hole'
        textures{2} = {n_pillar, [0, 0, varargin{1}, varargin{1}, n_background, 1]};
    case 'rectangle_hole'
        textures{2} = {n_pillar, [0, 0, varargin{1}, varargin{2}, n_background, 1]};
    case 'circle_hole'
        textures{2} = {n_pillar, [0, 0, varargin{1}, varargin{1}, n_background, 36]};
    case 'circle_hole_2' %% Circle hole but with extra pillar material on top of Substrate
        textures{2} = {n_pillar, [0, 0, varargin{1}, varargin{1}, n_background, 36]};
    case 'Au_circle'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
    case 'Circle_on_LI_on_HI_waveguide'
        textures{2} = {n_background, [0, 0, varargin{1}, varargin{1}, n_pillar, 36]};
    case 'circle_coat'
        diameter = varargin{1};
        thick = varargin{2};
        n_coat = varargin{3};
        textures{2} = {n_background, [0,0,diameter+2*thick,diameter+2*thick,n_coat,36]};
        textures{3} = {n_background, [0,0,diameter+2*thick,diameter+2*thick,n_coat,36], [0,0,diameter,diameter,n_pillar,36]};
        textures{4} = {n_coat, [0,0,diameter,diameter,n_pillar,36]};
    case 'square_coat'
        width = varargin{1};
        thick = varargin{2};
        n_coat = varargin{3};
        textures{2} = {n_background, [0,0,width+2*thick,width+2*thick,n_coat,1]};
        textures{3} = {n_background, [0,0,width+2*thick,width+2*thick,n_coat,1], [0,0,width,width,n_pillar,1]};
        textures{4} = {n_coat, [0,0,width,width,n_pillar,1]};
    case 'circle_emb'
        diameter = varargin{1};
        thick = varargin{2};
        n_coat = varargin{3};
        textures{2} = n_coat;
        textures{3} = {n_coat, [0,0,diameter,diameter,n_pillar,36]};
    otherwise
        error('pillar type not recognized. Look at RCWA.m code on what types are supported')
end
if strcmpi(pillar_type,'circle_coat')
    textures{5} = n_substrate;
elseif strcmpi(pillar_type,'square_coat')
    textures{5} = n_substrate;    
elseif strcmpi(pillar_type,'circle_on_circle')
    textures{5} = n_substrate;  
elseif strcmpi(pillar_type,'circle_emb')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type,'Au_circle')
    textures{3} = n_substrate;
    textures{4} = n_pillar;
elseif strcmpi(pillar_type, 'circle_hole_2')
    textures{3} = n_pillar;
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'circle_2')
    textures{3} = n_pillar;
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'circle_with_cap')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'square_with_cap')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'cross_with_cap')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'elliptical_cross_with_cap')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'Complex_Cross_1')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'Complex_Cross_2')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'Complex_Cross_Winston')
    textures{4} = n_substrate;
elseif strcmpi(pillar_type, 'Complex_Cross_3')
    textures{4} = n_substrate;
else
    textures{3} = n_substrate;
end

%% Define Profile and Run RCWA solver

if strcmpi(pillar_type,'circle_coat')
    profile = {[0, thick, height-thick, thick,0],[1,2,3,4,5]};
elseif strcmpi(pillar_type,'square_coat')
    profile = {[0, thick, height-thick, thick,0],[1,2,3,4,5]};
elseif strcmpi(pillar_type,'circle_emb')
    profile = {[0, thick, height,0],[1,2,3,4]};
elseif strcmpi(pillar_type, 'Au_circle')
    profile = {[0, height_pillar, height_spacer, 0.01], [1,2,3,4]};
elseif strcmpi(pillar_type, 'circle_hole_2')
    profile = {[0, height, varargin{2}, 0], [1,2,3,4]};  
elseif strcmpi(pillar_type, 'circle_with_cap')
    h_cap = varargin{2};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'square_with_cap')
    h_cap = varargin{2};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'cross_with_cap')
    h_cap = varargin{3};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'elliptical_cross_with_cap')
    h_cap = varargin{3};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'Complex_Cross_1')
    h_cap = varargin{4};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'Complex_Cross_2')
    h_cap = varargin{4};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'Complex_Cross_Winston')
    h_cap = varargin{4};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'Complex_Cross_3')
    h_cap = varargin{4};
    profile = {[0, h_cap, height, 0], [1, 2, 3, 4]};
elseif strcmpi(pillar_type, 'circle_2')
    profile = {[0, height, varargin{2}, 0], [1,2,3,4]};
elseif strcmpi(pillar_type, 'circle_on_circle')
    % varargin{1} = diameter
    % varargin{2} = height_top_layer
    % varargin{3} = height_spacer
    profile = {[0, varargin{2}, varargin{3}, height, 0], [1,2,3,4,5]}; 

else
                                       %background on top   (1 thick)
    profile = {[0,height,0],[1,2,3]};  %array in middle (H thick)
                                       %substrate on bottom (1 thick)
end

delta = 90;
theta = (angle_of_incidence);
% k_par = sind(theta); 
k_par = n_background * sind(theta);

aa = res1(wavelength, [period,period], textures, [12,12], k_par, delta, parm); %% Check for convergence by changing no of Fourier Harmonics [6,6]
result = res2(aa,profile);
if parm.sym.pol == 1 % TE Polarization
    transmitted = result.TEinc_bottom_transmitted.amplitude_TE{0};
    trans_efficiency = result.TEinc_bottom_transmitted.efficiency{0};
    reflected = result.TEinc_bottom_reflected.amplitude_TE{0};
    refl_efficiency = result.TEinc_bottom_reflected.efficiency{0};
elseif parm.sym.pol == -1 % TM Polarization
    % Note: For TM incidence, the output can still have TE and TM components.
    % We will assume you are interested in the co-polarized TM transmission.
    transmitted = result.TMinc_bottom_transmitted.amplitude_TM{0};
    trans_efficiency = result.TMinc_bottom_transmitted.efficiency{0};
    reflected = result.TMinc_bottom_reflected.amplitude_TM{0};
    refl_efficiency = result.TMinc_bottom_reflected.efficiency{0};
else
    error('Polarization not specified correctly in parm.sym.pol');
end


