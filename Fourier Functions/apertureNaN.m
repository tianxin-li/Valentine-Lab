%this function create an aperture with diameter of D
%--------------------------------------------------------------------------
function field = apertureNaN(x,y,D,x0,y0)

if ~exist('x0','var'); x0 = 0; end
if ~exist('y0','var'); y0 = zeros(size(x0)); end

field = ones(length(y),length(x));
for i = 1:length(x0)
    field(((x-x0(i)).^2+(y-y0(i)).^2)>=(D/2)^2)=NaN;
end
end