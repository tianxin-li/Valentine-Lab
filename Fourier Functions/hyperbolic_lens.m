function [trans,phase,xx] = hyperbolic_lens(D,flength,wavelength,pitch)
%this function will create a transmission matrix with hyperbolic phase profile
%Inputs must use matching units
%   D           : diameter of the lens
%   flength     : focal length of the lens
%   wavelength  : design wavelength
%   pitch       : distance between elements
%Outputs
%   trans       : complex transmittance matrix of lens
%   phase       : phase profile of lens
%   xx          : position of each element
    N = ceil(D / pitch);
    xx = meshgrid(((0:N-1) - floor(N/2))*pitch);
    xx2 = xx.^2;
    
    trans = exp(2i*pi/wavelength*(flength-sqrt(xx2 + xx2' + flength^2)) + 1i*pi).*aperture(xx,D);
    phase = angle(trans).*apertureNaN(xx,D);
end

function field = apertureNaN(x,D)
field = ones(size(x));
field(x.^2+x'.^2 > (D/2)^2) = NaN;
end

%--------------------------------------------------------------------------
function field = aperture(x,D)

field = x.^2+x'.^2 <= (D/2)^2;
end