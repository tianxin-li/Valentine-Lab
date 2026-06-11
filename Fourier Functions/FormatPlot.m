function [] = FormatPlot()
lines = get(gca, 'children');
for i = 1:size(lines,1)
    if strcmp(lines(i).Type,'line')
        set(lines(i), 'LineWidth', 1.5)
        set(lines(i), 'MarkerSize',5)
    end
end

% Labels
set(gca, 'LineWidth', 1.5, 'FontSize', 12, 'FontWeight', 'bold');
set(get(gca, 'XLabel'), 'FontSize', 14, 'FontWeight', 'bold');
set(get(gca, 'YLabel'), 'FontSize', 14, 'FontWeight', 'bold');
set(get(gca, 'Title'), 'FontSize', 16, 'FontWeight', 'bold');
set(gcf, 'Color', 'w');
% grid on
box on
end