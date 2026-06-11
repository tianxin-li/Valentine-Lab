function geom = parse_filter_geometry_name(name)
% PARSE_FILTER_GEOMETRY_NAME  Parse library-style filter geometry labels.
%
% Examples:
%   Height_1.30_Pitch_1.15_Width_0.514_AspectRatio_0.20_Cross
%   Height_1.30_Pitch_1.20_Diameter_0.237_Si_Pillars

    txt = char(string(name));
    geom = struct();
    geom.raw = txt;
    geom.shape = "unknown";
    geom.height = token_number(txt, 'Height_([0-9.]+)');
    geom.pitch = token_number(txt, 'Pitch_([0-9.]+)');
    geom.width = token_number(txt, 'Width_([0-9.]+)');
    geom.diameter = token_number(txt, 'Diameter_([0-9.]+)');
    geom.aspect_ratio = token_number(txt, 'AspectRatio_([0-9.]+)');
    if isnan(geom.aspect_ratio)
        geom.aspect_ratio = token_number(txt, 'AR_([0-9.]+)');
    end

    if contains(txt, 'Cross', 'IgnoreCase', true)
        geom.shape = "cross";
    elseif contains(txt, 'Pillars', 'IgnoreCase', true) || ...
            contains(txt, 'Circle', 'IgnoreCase', true)
        geom.shape = "circle";
    elseif contains(txt, 'Square', 'IgnoreCase', true)
        geom.shape = "square";
    elseif contains(txt, 'Ellipse', 'IgnoreCase', true)
        geom.shape = "ellipse";
    end
end

function val = token_number(txt, expr)
    tok = regexp(txt, expr, 'tokens', 'once');
    if isempty(tok)
        val = NaN;
    else
        val = str2double(tok{1});
    end
end
