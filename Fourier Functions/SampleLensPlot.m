clc; clearvars;

% Define parameters
D = 12700;
wavelength = 3.6;
pitch = 1.8;
flength = 15000;
N = ceil(D / pitch);

% Call function "hyperbolic lens" to compute the transmission matrix and
% phase profile of the lens
[complex_trans,phase,xx] = hyperbolic_lens(D,flength,wavelength,pitch);

% define the aperture as a mask that is 1 inside the lens and 0 outside the lens
aperture = ~isnan(phase);

%display the phase profile, using the aperture mask to set the alpha channel, so the data only displays where the lens is defined
figure(1)
corner = [min(xx,[],'all'), max(xx,[],'all')];
imagesc(corner, corner, phase,'AlphaData',aperture)

title('Hyperbolic lens phase profile, wrapped to (-\pi, \pi]')
c = colorbar;
c.Label.String = 'Phase';
axis image
set(gcf, 'Color', 'w');

