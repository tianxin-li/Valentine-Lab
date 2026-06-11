function G = check_grating_orders(period, wavelengths, n_substrate, ...
        n_background, theta, max_order, incident_side)
% CHECK_GRATING_ORDERS  Analytical grating equation analysis — no RCWA needed.
%
%   G = check_grating_orders(period, wavelengths, n_substrate,
%       n_background, theta, max_order, incident_side)
%
%   For a square-lattice metasurface, determines which diffraction orders
%   (m, n) are PROPAGATIVE at each wavelength in each medium (substrate
%   and background/air), using the grating equation directly. Run this
%   BEFORE a library sweep to understand which parts of your wavelength
%   range are truly subwavelength and which will have higher-order leakage.
%
%   A non-zero order that is propagative will carry away power, causing
%   T_0 + R_0 < T_all + R_all. Use this map to interpret energy balance
%   logs from the pipeline and to choose periods that remain subwavelength
%   across the full band of interest.
%
% -----------------------------------------------------------------------
%   GRATING EQUATION (square lattice, 2D)
% -----------------------------------------------------------------------
%   Order (m, n) is PROPAGATIVE in a medium with refractive index n_med if:
%
%     (k_x_inc + m * 2π/period)^2 + (k_y_inc + n * 2π/period)^2
%                 < (2π * n_med / λ)^2
%
%   For normal incidence (θ = 0): k_x_inc = k_y_inc = 0, so:
%
%     (m^2 + n^2) < (n_med * period / λ)^2
%
%   Cutoff wavelength for order (m, n) in medium n_med:
%
%     λ_cutoff(m,n) = period * n_med / sqrt(m^2 + n^2)
%
%   Key cutoffs for a SWIR example (period = 1.125 μm, n_sub = 1.45):
%     ±1 orders in substrate : λ < 1.125 × 1.45 = 1.631 μm
%     ±1 orders in air       : λ < 1.125 × 1.0  = 1.125 μm
%     ±1,±1 diagonal orders  : λ < 1.125 × 1.45 / √2 ≈ 1.153 μm (substrate)
%
% -----------------------------------------------------------------------
%   INPUTS
% -----------------------------------------------------------------------
%   period       : unit-cell pitch (um), scalar (square lattice assumed)
%   wavelengths  : wavelength vector (um), e.g. linspace(0.8, 1.7, 200)
%   n_substrate  : substrate refractive index (real scalar)
%   n_background : background index (real scalar, typically 1 for air)
%   theta        : angle of incidence in degrees (default 0)
%   max_order    : maximum |m| and |n| to check (default 3)
%                  Orders beyond this are almost certainly evanescent.
%   incident_side: 'air'/'top' or 'substrate'/'bottom' (default 'air').
%                  The production workflow defines theta as the
%                  air-side/effective angle, so RCWA_solve uses
%                  n_background * sind(theta).
%
% -----------------------------------------------------------------------
%   OUTPUT STRUCT G
% -----------------------------------------------------------------------
%   .wavelengths          input wavelength vector
%   .period, .n_sub, .n_bg, .theta   echoed inputs
%   .incident_side, .n_incident       side/index used for k_parallel
%
%   .n_prop_sub   [1 x Nw]  number of propagative orders in substrate
%   .n_prop_bg    [1 x Nw]  number of propagative orders in background
%   .n_hoe_sub    [1 x Nw]  number of HIGHER (non-zero) propagative orders
%                            in substrate  (= n_prop_sub - 1)
%   .n_hoe_bg     [1 x Nw]  higher-order count in background
%   .hoe_active   [1 x Nw]  logical — true when ANY higher-order mode is
%                            propagative in EITHER medium
%
%   .cutoffs      table     cutoff wavelengths for each order in each medium
%
%   .lambda_sub_1 scalar    λ below which ±1 orders propagate in substrate
%   .lambda_bg_1  scalar    λ below which ±1 orders propagate in background
%
%   .fig          figure handle (empty if display was suppressed)
%
% -----------------------------------------------------------------------
%   USAGE EXAMPLE
% -----------------------------------------------------------------------
%   G = check_grating_orders(1.125, linspace(0.8, 1.7, 200), 1.45, 1, 0);
%   % Above prints a summary and shows a figure.
%   % G.hoe_active marks wavelengths with higher-order diffraction.

    if nargin < 5 || isempty(theta),     theta     = 0; end
    if nargin < 6 || isempty(max_order), max_order = 3; end
    if nargin < 7 || isempty(incident_side), incident_side = 'air'; end

    % Backward-compatible convenience:
    % check_grating_orders(..., theta, 'top') treats the string as incident_side.
    if ischar(max_order) || isstring(max_order)
        incident_side = max_order;
        max_order = 3;
    end

    incident_side = lower(strtrim(char(incident_side)));
    switch incident_side
        case {'bottom', 'substrate'}
            incident_side = 'substrate';
            n_incident = n_substrate;
            incident_label = 'substrate-side angle';
        case {'top', 'air', 'background'}
            incident_side = 'air';
            n_incident = n_background;
            incident_label = 'air-side/effective angle';
        otherwise
            error('check_grating_orders:badIncidentSide', ...
                'incident_side must be ''air''/''top'' or ''substrate''/''bottom''; got "%s".', ...
                incident_side);
    end

    wavelengths = wavelengths(:).';
    Nw          = numel(wavelengths);

    % Incident k-components (normalized, in vacuum units)
    k_x_inc = n_incident * sind(theta);   % along x (delta=90 convention)
    k_y_inc = 0;

    % All (m, n) order pairs to test
    orders = [];
    for m = -max_order:max_order
        for n = -max_order:max_order
            orders(end+1, :) = [m, n]; %#ok<AGROW>
        end
    end
    N_orders = size(orders, 1);

    % --- compute propagation condition at each wavelength ---------------
    n_prop_sub = zeros(1, Nw);
    n_prop_bg  = zeros(1, Nw);

    for wi = 1:Nw
        lam = wavelengths(wi);
        for oi = 1:N_orders
            m = orders(oi, 1);
            n = orders(oi, 2);

            kx_m = k_x_inc + m / period;   % in units of 1/λ  (k_parallel/k0)
            ky_n = k_y_inc + n / period;

            % Propagative if k_parallel^2 < (n_med)^2
            k_par_sq = (lam * kx_m)^2 + (lam * ky_n)^2;

            if k_par_sq < n_substrate^2
                n_prop_sub(wi) = n_prop_sub(wi) + 1;
            end
            if k_par_sq < n_background^2
                n_prop_bg(wi) = n_prop_bg(wi) + 1;
            end
        end
    end

    % Zeroth order is always propagative; HOE = everything else
    n_hoe_sub = n_prop_sub - 1;
    n_hoe_bg  = n_prop_bg  - 1;
    hoe_active = (n_hoe_sub > 0) | (n_hoe_bg > 0);

    % --- analytical cutoff wavelengths for lowest orders ---------------
    lambda_sub_1 = period * n_substrate;      % ±1 orders, substrate
    lambda_bg_1  = period * n_background;     % ±1 orders, background

    % Build cutoff table
    cutoff_orders = {[1,0],[1,1],[2,0],[2,1],[2,2],[3,0]};
    cutoff_labels = {'(1,0)','(1,1)','(2,0)','(2,1)','(2,2)','(3,0)'};
    Nco = numel(cutoff_orders);
    lc_sub = zeros(1, Nco);
    lc_bg  = zeros(1, Nco);
    for ci = 1:Nco
        mn = cutoff_orders{ci};
        denom = sqrt(mn(1)^2 + mn(2)^2);
        lc_sub(ci) = period * n_substrate  / denom;
        lc_bg(ci)  = period * n_background / denom;
    end

    % Print summary
    fprintf(['\n=== Grating Order Analysis: period=%.3f um, n_sub=%.3f, ' ...
        'n_bg=%.2f, theta=%g deg, incident=%s (n=%.3f) ===\n'], ...
        period, n_substrate, n_background, theta, incident_label, n_incident);
    fprintf('%-10s  %-20s  %-20s\n', 'Order', 'Cutoff in substrate', 'Cutoff in background');
    fprintf('%s\n', repmat('-', 1, 55));
    for ci = 1:Nco
        sub_str = sprintf('%.3f um', lc_sub(ci));
        bg_str  = sprintf('%.3f um', lc_bg(ci));
        inrange_sub = (lc_sub(ci) >= wavelengths(1)) && (lc_sub(ci) <= wavelengths(end));
        inrange_bg  = (lc_bg(ci)  >= wavelengths(1)) && (lc_bg(ci)  <= wavelengths(end));
        if inrange_sub, sub_str = [sub_str '  *** IN RANGE ***']; end %#ok<AGROW>
        if inrange_bg,  bg_str  = [bg_str  '  *** IN RANGE ***']; end %#ok<AGROW>
        fprintf('%-10s  %-34s  %s\n', cutoff_labels{ci}, sub_str, bg_str);
    end

    hoe_frac = mean(hoe_active) * 100;
    if hoe_frac > 0
        fprintf('\nHigher-order modes ACTIVE in %.0f%% of wavelength range.\n', hoe_frac);
        fprintf('HOE begins below lambda = %.4f um.\n', max(wavelengths(hoe_active)));
    else
        fprintf('\nNo higher-order modes in this wavelength range. Fully subwavelength.\n');
    end

    % --- figure ---------------------------------------------------------
    fig = figure('Name', 'Grating Order Analysis', 'Position', [80 80 1050 700]);

    % Top: number of propagative higher-order modes vs wavelength
    ax1 = subplot(2, 1, 1);
    hold(ax1, 'on');
    area(ax1, wavelengths, n_hoe_sub, ...
        'FaceColor', [0.82 0.28 0.18], 'FaceAlpha', 0.55, ...
        'EdgeColor', [0.82 0.18 0.10], 'LineWidth', 1.2, ...
        'DisplayName', 'Higher orders in substrate');
    area(ax1, wavelengths, n_hoe_bg, ...
        'FaceColor', [0.18 0.42 0.78], 'FaceAlpha', 0.55, ...
        'EdgeColor', [0.10 0.28 0.70], 'LineWidth', 1.2, ...
        'DisplayName', 'Higher orders in background');
    hold(ax1, 'off');
    ylabel(ax1, 'Number of HOE modes');
    title(ax1, sprintf( ...
        'Propagative higher-order modes | period=%.3f\\mum | \\theta=%g\\circ', ...
        period, theta));
    legend(ax1, 'Location', 'northeast');
    grid(ax1, 'on'); box(ax1, 'on');
    xlim(ax1, [wavelengths(1) wavelengths(end)]);
    ylim(ax1, [0 max(max(n_hoe_sub), max(n_hoe_bg)) + 1]);
    yticks(ax1, 0:ceil(max(max(n_hoe_sub), max(n_hoe_bg))+1));

    % Add vertical cutoff lines for ±1 orders
    if lambda_bg_1 >= wavelengths(1) && lambda_bg_1 <= wavelengths(end)
        xline(ax1, lambda_bg_1, '--', ...
            sprintf(' (\\pm1) in air \\lambda=%.3f\\mum', lambda_bg_1), ...
            'Color', [0.18 0.42 0.78], 'LineWidth', 1.5, ...
            'LabelVerticalAlignment', 'bottom');
    end
    if lambda_sub_1 >= wavelengths(1) && lambda_sub_1 <= wavelengths(end)
        xline(ax1, lambda_sub_1, '--', ...
            sprintf(' (\\pm1) in substrate \\lambda=%.3f\\mum', lambda_sub_1), ...
            'Color', [0.82 0.28 0.18], 'LineWidth', 1.5, ...
            'LabelVerticalAlignment', 'bottom');
    end

    % Bottom: shaded map of which wavelengths have HOE active
    ax2 = subplot(2, 1, 2);
    imagesc(ax2, wavelengths, [0.5 1.5], double(hoe_active));
    colormap(ax2, [0.92 0.96 0.92; 0.85 0.22 0.15]);
    yticks(ax2, 1); yticklabels(ax2, {'HOE active?'});
    xlabel(ax2, 'Wavelength (\mum)');
    title(ax2, 'Green = subwavelength (HOE inactive)   |   Red = HOE active');
    xlim(ax2, [wavelengths(1) wavelengths(end)]);
    box(ax2, 'on');

    % --- pack output ----------------------------------------------------
    G.wavelengths  = wavelengths;
    G.period       = period;
    G.n_sub        = n_substrate;
    G.n_bg         = n_background;
    G.theta        = theta;
    G.incident_side = incident_side;
    G.angle_reference = incident_side;
    G.n_incident  = n_incident;
    G.n_prop_sub   = n_prop_sub;
    G.n_prop_bg    = n_prop_bg;
    G.n_hoe_sub    = n_hoe_sub;
    G.n_hoe_bg     = n_hoe_bg;
    G.hoe_active   = hoe_active;
    G.lambda_sub_1 = lambda_sub_1;
    G.lambda_bg_1  = lambda_bg_1;

    % Build cutoffs struct
    G.cutoffs.orders     = cutoff_labels;
    G.cutoffs.lambda_sub = lc_sub;
    G.cutoffs.lambda_bg  = lc_bg;

    G.fig = fig;
end
