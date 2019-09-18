% ------------------------------------------------------------------------
%          Display Probe Track
% ------------------------------------------------------------------------

%% ENTER PARAMETERS AND FILE LOCATION

% file location of probe points
processed_images_folder = '/home/maxime/Documents/allenCCF/brains/YC010/ccf_alignement/processed';

% directory of reference atlas files
annotation_volume_location = '/home/maxime/Documents/allenCCF/allen_atlas/annotation_volume_10um_by_index.npy';
structure_tree_location = '/home/maxime/Documents/allenCCF/allen_atlas/structure_tree_safe_2017.csv';

% directory of the probe channel map, to relate depth to channel index
channel_pos_path = '/home/maxime/Documents/allenCCF/channel_maps/Neuropixels_1.0/channel_positions.npy';

% name of the saved probe points
probe_save_name_suffix = 'track_left_';
%probe_save_name_suffix = 'track_right_';
% either set to 'all' or a list of indices from the clicked probes in this file, e.g. [2,3]
probes_to_analyze = 'all';  % [1 2]

% -----------
% parameters
% -----------
% how far into the brain did you go from the surface, either for each probe or just one number for all -- in mm
probe_lengths = 4; 

% from the bottom tip, how much of the probe contained recording sites -- in mm
active_probe_length = 3.84;

% distance queried for confidence metric -- in um
probe_radius = 100; 

% overlay the distance between parent regions in gray (this takes a while)
show_parent_category = true; 

% plot this far or to the bottom of the brain, whichever is shorter -- in mm
distance_past_tip_to_plot = 0.3; % Just a display variable, does not impact results

% set scaling e.g. based on lining up the ephys with the atlas
% set to *false* to get scaling automatically from the clicked points
scaling_factor = false; 

% show a table of regions that the probe goes through, in the console
show_region_table = true;
      
% black brain?
black_brain = true;


% close all




%% GET AND PLOT PROBE VECTOR IN ATLAS SPACE

% load the reference brain annotations
if ~exist('av','var') || ~exist('st','var')
    disp('loading reference atlas...')
    av = readNPY(annotation_volume_location);
    st = loadStructureTree(structure_tree_location);
end

% load probe points
probePoints = load(fullfile(processed_images_folder, ['probe_points' probe_save_name_suffix]));
ProbeColors = .75*[1.3 1.3 1.3; 1 .75 0;  .3 1 1; .4 .6 .2; 1 .35 .65; .7 .7 .9; .65 .4 .25; .7 .95 .3; .7 0 0; .6 0 .7; 1 .6 0]; 
% order of colors: {'white','gold','turquoise','fern','bubble gum','overcast sky','rawhide', 'green apple','purple','orange','red'};
fwireframe = [];

% scale active_probe_length appropriately
active_probe_length = active_probe_length*100;

% determine which probes to analyze
if strcmp(probes_to_analyze,'all')
    probes = 1:size(probePoints.pointList.pointList,1);
else
    probes = probes_to_analyze;
end 





%% PLOT EACH PROBE -- FIRST FIND ITS TRAJECTORY IN REFERENCE SPACE

for selected_probe = probes
    
% get the probe points for the currently analyzed probe    
curr_probePoints = probePoints.pointList.pointList{selected_probe,1}(:, [3 2 1]);

% get user-defined probe length from experiment
if length(probe_lengths) > 1
    probe_length = probe_lengths(selected_probe);
else
    probe_length = probe_lengths;
end

% get the scaling-factor method to use
if scaling_factor
    use_tip_to_get_reference_probe_length = false;
    reference_probe_length = probe_length * scaling_factor;
    disp(['probe scaling of ' num2str(scaling_factor) ' determined by user input']);    
else
    use_tip_to_get_reference_probe_length = true;
    disp(['getting probe scaling from histology data...']);
end

% get line of best fit through points
% m is the mean value of each dimension; p is the eigenvector for largest eigenvalue
[m,p,s] = best_fit_line(curr_probePoints(:,1), curr_probePoints(:,2), curr_probePoints(:,3));
if isnan(m(1))
    disp(['no points found for probe ' num2str(selected_probe)])
    continue
end

% ensure proper orientation: want 0 at the top of the brain and positive distance goes down into the brain
if p(2)<0
    p = -p;
end

% determine "origin" at top of brain -- step upwards along tract direction until tip of brain / past cortex
ann = 10;
isoCtxId = num2str(st.id(strcmp(st.acronym, 'root')));%num2str(st.id(strcmp(st.acronym, 'Isocortex')));
gotToCtx = false;
while ~(ann==1 && gotToCtx)
    m = m-p; % step 10um, backwards up the track
    ann = av(round(m(1)),round(m(2)),round(m(3))); %until hitting the top
    if ~isempty(strfind(st.structure_id_path{ann}, isoCtxId))
        % if the track didn't get to cortex yet, keep looking...
        gotToCtx = true;
    end
end

% plot brain grid
fwireframe = plotBrainGrid([], [], fwireframe, black_brain); hold on; 
fwireframe.InvertHardcopy = 'off';

% plot probe points
hp = plot3(curr_probePoints(:,1), curr_probePoints(:,3), curr_probePoints(:,2), '.','linewidth',2, 'color',[ProbeColors(selected_probe,:) .2],'markers',10);

% plot brain entry point
plot3(m(1), m(3), m(2), 'r*','linewidth',3)

% use the deepest clicked point as the tip of the probe, if no scaling provided (scaling_factor = false)
if use_tip_to_get_reference_probe_length
    % find length of probe in reference atlas space
    [depth, tip_index] = max(curr_probePoints(:,2));
    reference_probe_length_tip = sqrt(sum((curr_probePoints(tip_index,:) - m).^2)); 
    
    % and the corresponding scaling factor
    shrinkage_factor = (reference_probe_length_tip / 100) / probe_length; % 100 factior because units are atlas pixels (10um/pixel)
    
    % display the scaling
    disp(['probe length of ' num2str(reference_probe_length_tip/100) ' mm in reference atlas space compared to a reported ' num2str(probe_length) ' mm']);
    disp(['probe scaling of ' num2str(shrinkage_factor)]); disp(' ');
    
    % plot line the length of the probe in reference space
    probe_length_histo = round(reference_probe_length_tip);
    
% if scaling_factor is user-defined as some numer, use it to plot the length of the probe
else 
    probe_length_histo = round(reference_probe_length * 100); 
end

% find the percent of the probe occupied by electrodes
percent_of_tract_with_active_sites = min([active_probe_length / (probe_length*100), 1.0]);
active_site_start = probe_length_histo*(1-percent_of_tract_with_active_sites);
active_probe_position = round([active_site_start  probe_length_histo]);

% plot line the length of the active probe sites in reference space
plot3(m(1)+p(1)*[active_probe_position(1) active_probe_position(2)], m(3)+p(3)*[active_probe_position(1) active_probe_position(2)], m(2)+p(2)*[active_probe_position(1) active_probe_position(2)], ...
    'Color', ProbeColors(selected_probe,:), 'LineWidth', 1);
% plot line the length of the entire probe in reference space
plot3(m(1)+p(1)*[1 probe_length_histo], m(3)+p(3)*[1 probe_length_histo], m(2)+p(2)*[1 probe_length_histo], ...
    'Color', ProbeColors(selected_probe,:), 'LineWidth', 1, 'LineStyle',':');


%% ----------------------------------------------------------------
% Get and plot brain region labels along the extent of each probe
% and save table of registered channels with respective brain region etc
% ----------------------------------------------------------------

% convert error radius into mm
error_length = round(probe_radius / 10);

% find and regions the probe goes through, confidence in those regions, and plot them
[borders, regions, distance_to_nearest] = plotDistToNearestToTip(m, p, av, st, probe_length_histo, error_length, active_site_start, distance_past_tip_to_plot, show_parent_category, show_region_table); % plots confidence score based on distance to nearest region along probe
title(['Probe ' num2str(selected_probe)],'color',ProbeColors(selected_probe,:))
% rpl=probe_length_histo; probage_past_tip_to_plot=distance_past_tip_to_plot;

% Export the data as a Nchan*8 matrix 'channel #, x, relative_z, absolute_x, absolute_y, absolute_z, region, confidence (distance to nearest other region in um)'
channel_pos=readNPY(channel_pos_path);
Nchan=size(channel_pos, 1);
%registered_channels = table('size', [Nchan, 8], 'VariableTypes', {'int32', 'double', 'double', 'double', 'double', 'double', 'string', 'double'});
channels=transpose(Nchan:-1:1);
rel_x=channel_pos(:,1);
rel_z=channel_pos(:,2);
% m is the top of the brain, positive distance (p(2)) goes down the brain
pixel_chan1=probe_length_histo*(1-percent_of_tract_with_active_sites);
pixel_chanlast=probe_length_histo;
track_pixels=pixel_chan1+shrinkage_factor*rel_z/10;
abs_y = round(m(1)+p(1)*track_pixels*10); % Track_y, in microns (10 microns/pixel)
abs_z = round(m(2)+p(2)*track_pixels*10); % Track_z, in microns (10 microns/pixel)
abs_x = round(m(3)+p(3)*track_pixels*10); % Track_x, in microns (10 microns/pixel)
abs_d=round(track_pixels*10);

chan_regs=cell(Nchan, 1);
chan_conf=cell(Nchan, 1);
for i=1:size(channels, 1)
    abs_depth=rel_z(i)/10+borders(2);
    reg=regions(abs_depth>borders);reg=reg{end};
    chan_regs{i}=reg;
    chan_conf{i}=distance_to_nearest(abs_depth)*10;
end

registered_channels=table(channels, rel_x, rel_z, abs_x, abs_y, abs_z, abs_d, chan_regs, chan_conf,...
    'VariableNames', {'channels', 'relativeX_um', 'relativeZ_um', 'absoluteX_um',...
    'absoluteY_um', 'absoluteZ_um', 'absoluteD_um', 'CCFregion', 'confidence_distToNearesstRegion_um'});
writetable(registered_channels, strcat(processed_images_folder, '/registered_channels.csv'))

pause(.05)
end
