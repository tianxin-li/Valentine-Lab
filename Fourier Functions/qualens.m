%this function will create a metalens with quadratic phase profile
%D is diameter of the lens
%--------------------------------------------------------------------------
function [lens, phase] = qualens(x,y,D,fnumber,lambda)
    [theta,rho] = cart2pol(x,y);
    f = D*fnumber;
    phase = -2*pi/lambda*rho.^2/(2*f).*aperture(x,y,D);
    lens = exp(1i*phase).*aperture(x,y,D);
end