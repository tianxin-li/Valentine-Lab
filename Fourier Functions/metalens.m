%this function will create a metalens with hyperbolic phase profile
%D is diameter of the lens
%--------------------------------------------------------------------------
function [lens,phase] = metalens(x,y,D,fnumber,lambda)
    f = D*fnumber;
    phase = 2*pi/lambda*(f-sqrt(x.^2+y.^2+f^2)).*aperture(x,y,D);
    lens = exp(1i*phase).*aperture(x,y,D);
end