function results = check_convergence(spec, wavelength, height, n_substrate, ...
        n_pillar, n_background, n_cap, theta, period, p1, p2, h_cap, pol, ...
        nn_test, threshold)
% CHECK_CONVERGENCE  Verify Fourier-harmonic convergence for a given geometry.
%
%   results = check_convergence(spec, wavelength, height, n_substrate,
%       n_pillar, n_background, n_cap, theta, period, p1, p2, h_cap, pol,
%       nn_test, threshold)
%
%   Runs RCWA_solve at a sequence of nn values for a single representative
%   geometry and wavelength, then reports the transmission efficiency, the
%   step-to-step change |ΔT|, and the energy balance T+R. Returns the
%   smallest nn at which the result is considered converged and plots a
%   three-panel convergence figure.
%
%   Call this before committing to a library sweep to confirm that the
%   chosen nn is sufficient. Results vary by shape (circles need more nn
%   than squares due to staircase approximation) and by fill factor.
%
% -----------------------------------------------------------------------
%   INPUTS
% -----------------------------------------------------------------------
%   spec        : shape spec from shape_registry(shape_name)
%   wavelength  : single representative wavelength in um
%   height      : pillar height in um
%   n_substrate : substrate index
%   n_pillar    : pillar complex index at 'wavelength'
%   n_background: background index (typically 1)
%   n_cap       : cap layer index
%   theta       : incidence angle in degrees
%   period      : unit-cell pitch in um
%   p1          : first geometric parameter
%   p2          : second geometric parameter (1 for 1-param shapes)
%   h_cap       : cap thickness in um
%   pol         : +1 = TE, -1 = TM
%   nn_test     : vector of nn scalars to test, e.g. [4 6 8 10 12 15 20]
%                 (optional, default [4 6 8 10 12 15 20])
%   threshold   : convergence criterion on |ΔT| (optional, default 0.005)
%                 The recommended nn is the smallest where |ΔT| from the
%                 next nn value is below this threshold.
%
% -----------------------------------------------------------------------
%   OUTPUT STRUCT
% -----------------------------------------------------------------------
%   .nn_tested        [1 x N]  nn values tested
%   .trans_eff        [1 x N]  0-order transmission efficiency
%   .refl_eff         [1 x N]  0-order reflection efficiency
%   .energy_balance   [1 x N]  T + R  (1 = lossless; <1 = absorbing)
%   .delta_T          [1 x N]  |T(nn) - T(nn_prev)|; first entry = NaN
%   .recommended_nn   scalar   smallest nn where |ΔT| < threshold
%   .converged        logical  true if any nn in nn_test is recommended
%   .fig              handle   convergence figure handle

    if nargin < 14 || isempty(nn_test)
        nn_test = [4, 6, 8, 10, 12, 15, 20];
    end
    if nargin < 15 || isempty(threshold)
        threshold = 0.005;          % 0.5% change in T = converged
    end

    nn_test = nn_test(:).';         % ensure row vector
    N       = numel(nn_test);

    trans_eff      = zeros(1, N);
    refl_eff       = zeros(1, N);
    energy_balance = zeros(1, N);
    delta_T        = nan(1, N);

    pol_str = 'TE';
    if pol == -1, pol_str = 'TM'; end

    fprintf('\n=== Convergence check: %s, %s, \x03BB=%.4f\xB5m ===\n', ...
        spec.display_name, pol_str, wavelength);
    fprintf('%-8s  %-12s  %-12s  %-14s  %-10s\n', ...
        'nn', 'T_eff', 'R_eff', 'T+R (energy)', '|dT|');
    fprintf('%s\n', repmat('-', 1, 60));

    for i = 1:N
        nn_i = [nn_test(i), nn_test(i)];

        try
            [~, ~, te, re] = RCWA_solve(spec, wavelength, height, n_substrate, ...
                n_pillar, n_background, n_cap, theta, period, p1, p2, h_cap, ...
                pol, nn_i);
        catch ME
            warning('check_convergence:solveFailed', ...
                'RCWA_solve failed at nn=%d: %s', nn_test(i), ME.message);
            trans_eff(i)      = NaN;
            refl_eff(i)       = NaN;
            energy_balance(i) = NaN;
            continue;
        end

        trans_eff(i)      = te;
        refl_eff(i)       = re;
        energy_balance(i) = te + re;

        if i > 1
            delta_T(i) = abs(trans_eff(i) - trans_eff(i-1));
        end

        if i == 1
            dT_str = '    —';
        else
            dT_str = sprintf('%10.5f', delta_T(i));
        end
        fprintf('%-8d  %-12.6f  %-12.6f  %-14.6f  %s\n', ...
            nn_test(i), te, re, te+re, dT_str);
    end

    % --- find recommended nn ----------------------------------------
    % Recommended = smallest nn(i) such that delta_T(i+1) < threshold
    % (i.e., going from nn(i) to nn(i+1) changes T by less than threshold).
    % This means nn(i) is "good enough" since the next step changes little.
    recommended_nn = NaN;
    converged      = false;
    for i = 1:N-1
        if ~isnan(delta_T(i+1)) && delta_T(i+1) < threshold
            recommended_nn = nn_test(i);
            converged      = true;
            break;
        end
    end

    if converged
        fprintf('\nRECOMMENDED nn = %d  (|dT| < %.4f at nn=%d)\n', ...
            recommended_nn, threshold, nn_test(find(nn_test == recommended_nn)+1));
    else
        fprintf('\nNOT CONVERGED within tested nn range.\n');
        fprintf('Consider testing larger nn values. Max |dT| = %.5f\n', ...
            max(delta_T(~isnan(delta_T))));
    end

    if ~isnan(trans_eff(end)) && ~isnan(refl_eff(end))
        eb_final = trans_eff(end) + refl_eff(end);
        if eb_final < 0.98
            fprintf('NOTE: T+R = %.4f at nn=%d — absorption present (Si is lossy at this wavelength).\n', ...
                eb_final, nn_test(end));
        end
    end

    % --- build figure -----------------------------------------------
    fig = figure('Name', sprintf('Convergence: %s | %s | \x03BB=%.4f\xm', ...
        spec.display_name, pol_str, wavelength), ...
        'Position', [100 80 900 780]);

    % Subplot 1: T and R vs nn
    ax1 = subplot(3, 1, 1);
    hold(ax1, 'on');
    plot(ax1, nn_test, trans_eff, 'o-', ...
        'Color', [0.18 0.42 0.78], 'LineWidth', 2, ...
        'MarkerFaceColor', [0.18 0.42 0.78], 'MarkerSize', 7, ...
        'DisplayName', 'T_{eff}');
    plot(ax1, nn_test, refl_eff, 's--', ...
        'Color', [0.82 0.28 0.18], 'LineWidth', 1.5, ...
        'MarkerFaceColor', [0.82 0.28 0.18], 'MarkerSize', 6, ...
        'DisplayName', 'R_{eff}');
    if converged
        xline(ax1, recommended_nn, '--k', ...
            sprintf(' nn=%d (recommended)', recommended_nn), ...
            'LineWidth', 1.2, 'LabelVerticalAlignment', 'bottom');
    end
    hold(ax1, 'off');
    ylabel(ax1, 'Efficiency');
    legend(ax1, 'Location', 'best');
    title(ax1, sprintf('%s | %s | \\lambda=%.4f \\mum | \\theta=%g\\circ', ...
        spec.display_name, pol_str, wavelength, theta));
    grid(ax1, 'on'); box(ax1, 'on');
    ylim(ax1, [0 1]);
    xticks(ax1, nn_test);

    % Subplot 2: |delta_T| vs nn (convergence criterion)
    ax2 = subplot(3, 1, 2);
    valid = ~isnan(delta_T);
    semilogy(ax2, nn_test(valid), delta_T(valid), 'o-', ...
        'Color', [0.18 0.60 0.35], 'LineWidth', 2, ...
        'MarkerFaceColor', [0.18 0.60 0.35], 'MarkerSize', 7);
    yline(ax2, threshold, '--r', ...
        sprintf(' Threshold = %.4f', threshold), 'LineWidth', 1.2);
    ylabel(ax2, '|T(nn) - T(nn_{prev})|');
    title(ax2, 'Step-to-step change in T_{eff} (log scale)');
    grid(ax2, 'on'); box(ax2, 'on');
    xticks(ax2, nn_test);
    if any(~isnan(delta_T(valid)))
        ylim(ax2, [min(delta_T(valid)) * 0.5, max(delta_T(valid)) * 2]);
    end

    % Subplot 3: Energy balance T+R vs nn
    ax3 = subplot(3, 1, 3);
    hold(ax3, 'on');
    eb_valid = energy_balance;
    eb_valid(isnan(eb_valid)) = 0;
    bar(ax3, nn_test, eb_valid, 0.5, 'FaceColor', [0.65 0.45 0.82]);
    yline(ax3, 1.0, '--k', ' T+R = 1 (lossless)', 'LineWidth', 1.2);
    hold(ax3, 'off');
    xlabel(ax3, 'nn');
    ylabel(ax3, 'T + R');
    title(ax3, 'Energy balance (T+R < 1 indicates absorption or unconverged loss)');
    ylim(ax3, [0 1.05]);
    xticks(ax3, nn_test);
    grid(ax3, 'on'); box(ax3, 'on');

    for ax = [ax1 ax2 ax3]
        xlim(ax, [nn_test(1)-1, nn_test(end)+1]);
    end

    % --- pack results -----------------------------------------------
    results.nn_tested       = nn_test;
    results.trans_eff       = trans_eff;
    results.refl_eff        = refl_eff;
    results.energy_balance  = energy_balance;
    results.delta_T         = delta_T;
    results.recommended_nn  = recommended_nn;
    results.converged       = converged;
    results.threshold       = threshold;
    results.fig             = fig;
end
